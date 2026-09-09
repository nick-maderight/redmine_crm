// frozen_string_literal: true
(function () {
  "use strict";

  var csrfToken = function () {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  };

  var parseJson = function (value, fallback) {
    if (!value) return fallback;
    try {
      return JSON.parse(value);
    } catch (_error) {
      return fallback;
    }
  };

  var idFor = function (row) {
    var data = row && typeof row.getData === "function" ? row.getData() : row;
    return data && (data.id || data.record_id);
  };

  var expandUrl = function (template, id) {
    if (!template) return "";
    var encodedId = encodeURIComponent(id);
    if (template.indexOf(":id") !== -1) return template.replace(/:id/g, encodedId);
    if (template.indexOf("{id}") !== -1) return template.replace(/\{id\}/g, encodedId);
    if (template.indexOf("__ID__") !== -1) return template.replace(/__ID__/g, encodedId);
    if (id && /\/$/.test(template)) return template + encodedId;
    return template;
  };

  var recordCollection = function (grid) {
    var type = grid && grid.getAttribute("data-crm-record-type");
    return { account: "accounts", contact: "contacts", deal: "deals", activity: "activities" }[type] || "";
  };

  var rowUrl = function (grid, row, kind) {
    var data = row && typeof row.getData === "function" ? row.getData() : row || {};
    var id = idFor(row);
    var rowKey = kind + "_url";
    var template = data[rowKey] || data[kind + "Url"] || (kind === "open" ? data.url : null);
    if (!template && grid) template = grid.getAttribute("data-crm-" + kind + "-url");
    if (!template && grid && (kind === "open" || kind === "archive" || kind === "restore")) {
      template = grid.getAttribute("data-crm-update-url");
    }
    var expanded = expandUrl(template, id);
    if (expanded && (kind === "archive" || kind === "restore") && !new RegExp("/" + kind + "$", "u").test(expanded)) {
      expanded += "/" + kind;
    }
    return expanded;
  };

  var bulkUrl = function (grid) {
    return grid.getAttribute("data-crm-bulk-url") || (recordCollection(grid) ? "/crm/" + recordCollection(grid) + "/bulk" : "");
  };

  var recordFromResponse = function (payload) {
    if (!payload || typeof payload !== "object") return null;
    return payload.record || payload.row || payload.item || payload.data || payload;
  };

  var errorMessage = function (payload, fallback) {
    if (!payload) return fallback;
    if (typeof payload === "string") return payload;
    if (payload.error) return payload.error;
    if (payload.message) return payload.message;
    if (payload.errors) {
      if (typeof payload.errors === "string") return payload.errors;
      if (Array.isArray(payload.errors)) return payload.errors.join(", ");
      return Object.keys(payload.errors).map(function (key) {
        var value = payload.errors[key];
        return key + ": " + (Array.isArray(value) ? value.join(", ") : value);
      }).join("; ");
    }
    return fallback;
  };

  var requestJson = function (url, method, body) {
    var headers = {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": csrfToken()
    };
    return fetch(url, {
      method: method,
      credentials: "same-origin",
      headers: headers,
      body: body === undefined ? undefined : JSON.stringify(body)
    }).then(function (response) {
      return response.text().then(function (text) {
        var payload = parseJson(text, {});
        if (!response.ok) {
          var error = new Error(errorMessage(payload, "Request failed (" + response.status + ")"));
          error.status = response.status;
          error.payload = payload;
          throw error;
        }
        return payload;
      });
    });
  };

  var setCellError = function (cell, message, conflict) {
    var element = cell && cell.getElement ? cell.getElement() : null;
    if (!element) return;
    element.classList.add("crm-cell-error");
    if (conflict) element.classList.add("crm-cell-conflict");
    element.setAttribute("aria-invalid", "true");
    element.setAttribute("data-crm-error", message);
    element.title = message;
  };

  var clearCellError = function (cell) {
    var element = cell && cell.getElement ? cell.getElement() : null;
    if (!element) return;
    element.classList.remove("crm-cell-error", "crm-cell-conflict");
    element.removeAttribute("aria-invalid");
    element.removeAttribute("data-crm-error");
    element.removeAttribute("title");
  };

  var markGridError = function (grid, message) {
    if (!grid) return;
    grid.classList.add("crm-grid-error");
    grid.setAttribute("data-crm-error", message);
    grid.setAttribute("aria-errormessage", message);
    var status = grid.querySelector("[data-crm-grid-status]");
    if (status) status.textContent = message;
  };

  var updateRowFromResponse = function (row, payload) {
    var record = recordFromResponse(payload);
    if (!row || !record || typeof record !== "object" || Array.isArray(record)) return;
    if (typeof row.update === "function") row.update(record);
  };

  var editCell = function (grid, cell) {
    var row = cell.getRow();
    var data = row.getData() || {};
    var field = cell.getField();
    var value = cell.getValue();
    var oldValue = cell.getOldValue();
    var lockVersion = data.lock_version;
    var url = rowUrl(grid, row, "update");
    if (!url || !field) return;
    clearCellError(cell);
    var body = { lock_version: lockVersion };
    body[field] = value;
    requestJson(url, "PATCH", body).then(function (payload) {
      updateRowFromResponse(row, payload);
      var record = recordFromResponse(payload);
      if (record && record.lock_version !== undefined) {
        row.update({ lock_version: record.lock_version });
      } else if (payload && payload.lock_version !== undefined) {
        row.update({ lock_version: payload.lock_version });
      }
      clearCellError(cell);
    }).catch(function (error) {
      // Restore only this local edit. A conflict never reloads or overwrites the newer server row.
      cell.setValue(oldValue, true);
      setCellError(cell, errorMessage(error.payload, error.message), error.status === 409);
    });
  };

  var labels = function (grid, key, fallback) {
    if (!grid) return fallback;
    var attribute = "data-crm-label-" + key.replace(/_/g, "-");
    return grid.getAttribute(attribute) || fallback;
  };

  var removeMenu = function () {
    var current = document.querySelector(".crm-context-menu");
    if (current) current.remove();
  };

  var copyText = function (text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    var input = document.createElement("textarea");
    input.value = text;
    input.setAttribute("readonly", "readonly");
    input.style.position = "fixed";
    input.style.opacity = "0";
    document.body.appendChild(input);
    input.select();
    document.execCommand("copy");
    input.remove();
    return Promise.resolve();
  };

  var selectedRows = function (table, fallback) {
    var rows = table && table.getSelectedRows ? table.getSelectedRows() : [];
    if (!rows.length && fallback) rows = [fallback];
    return rows;
  };

  var applyBulkResponse = function (table, payload, action) {
    var rows = payload && (payload.rows || payload.records);
    if (Array.isArray(rows)) {
      rows.forEach(function (record) {
        var row = table.getRow(record.id || record.record_id);
        if (row) row.update(record);
      });
    }
    var results = payload && payload.results;
    if (Array.isArray(results)) {
      results.forEach(function (result) {
        var row = table.getRow(result.id);
        if (!row) return;
        if (result.error) {
          var element = row.getElement();
          element.classList.add("crm-cell-error");
          element.setAttribute("data-crm-error", result.error);
          element.title = result.error;
        } else {
          if (result.lock_version !== undefined) row.update({ lock_version: result.lock_version });
          if (action === "archive") row.delete();
        }
      });
    }
    var removed = payload && (payload.archived_ids || payload.removed_ids);
    if (Array.isArray(removed)) {
      removed.forEach(function (id) {
        var row = table.getRow(id);
        if (row) row.delete();
      });
    }
  };

  var performBulk = function (grid, table, fallbackRow, action, value) {
    var rows = selectedRows(table, fallbackRow);
    var ids = rows.map(idFor).filter(Boolean);
    var url = bulkUrl(grid);
    if (!url || !ids.length) return Promise.resolve();
    var records = {};
    rows.forEach(function (row) {
      var id = idFor(row);
      var data = row.getData() || {};
      var values = { lock_version: data.lock_version };
      if (action === "archive" || action === "restore") values.action = action;
      else if (action === "set_owner") values.owner_id = value;
      else if (action === "set_stage") values.stage_id = value;
      else values.action = action;
      records[id] = values;
    });
    return requestJson(url, "POST", { records: records }).then(function (payload) {
      applyBulkResponse(table, payload, action);
      return payload;
    }).catch(function (error) {
      markGridError(grid, errorMessage(error.payload, error.message));
    });
  };

  var promptValue = function (grid, key, fallback) {
    var promptText = labels(grid, key + "_prompt", fallback);
    return window.prompt(promptText);
  };

  var contextMenu = function (grid, table, event, row) {
    removeMenu();
    var menu = document.createElement("div");
    menu.className = "crm-context-menu";
    menu.setAttribute("role", "menu");
    menu.tabIndex = -1;
    var data = row.getData() || {};
    var openUrl = rowUrl(grid, row, "open") || data.url;
    var copyUrl = data.url || openUrl || window.location.href;
    var archiveUrl = rowUrl(grid, row, "archive");
    var restoreUrl = rowUrl(grid, row, "restore");
    var includeArchived = grid.hasAttribute("data-crm-include-archived") || grid.getAttribute("data-crm-include-archived") === "true" || /(?:include_archived|include-archived)=(?:1|true)/u.test(window.location.search);
    var selected = selectedRows(table, row).length;
    var add = function (key, text, callback) {
      if (!callback) return;
      var item = document.createElement("button");
      item.type = "button";
      item.className = "crm-context-menu-item";
      item.setAttribute("role", "menuitem");
      item.textContent = text;
      item.addEventListener("click", function () {
        removeMenu();
        callback();
      });
      menu.appendChild(item);
    };
    add("open", labels(grid, "open", "Open"), openUrl ? function () { window.location.assign(openUrl); } : null);
    add("copy_link", labels(grid, "copy_link", "Copy link"), function () {
      copyText(new URL(copyUrl, window.location.origin).href);
    });
    if (archiveUrl && !includeArchived) {
      add("archive", selected > 1 ? labels(grid, "archive_selected", "Archive selected") : labels(grid, "archive", "Archive"), function () {
        if (selected > 1) {
          performBulk(grid, table, row, "archive");
        } else {
          var version = (row.getData() || {}).lock_version;
          requestJson(archiveUrl, "PUT", { lock_version: version }).then(function (payload) {
            if (includeArchived && payload && payload.record) row.update(payload.record);
            else row.delete();
          }).catch(function (error) { markGridError(grid, errorMessage(error.payload, error.message)); });
        }
      });
    }
    if (restoreUrl && includeArchived) {
      add("restore", labels(grid, "restore", "Restore"), function () {
        var version = (row.getData() || {}).lock_version;
        requestJson(restoreUrl, "PUT", { lock_version: version }).then(function (payload) {
          if (payload && payload.record) row.update(payload.record);
          else row.delete();
        }).catch(function (error) { markGridError(grid, errorMessage(error.payload, error.message)); });
      });
    }
    var ownerCapability = grid.getAttribute("data-crm-can-set-owner");
    if (ownerCapability === "true" || (ownerCapability === null && ["account", "contact", "deal"].indexOf(grid.getAttribute("data-crm-record-type")) !== -1)) {
      add("set_owner", labels(grid, "set_owner", "Set owner"), function () {
        var value = promptValue(grid, "owner", "Owner id");
        if (value !== null) performBulk(grid, table, row, "set_owner", value);
      });
    }
    if (grid.getAttribute("data-crm-can-set-stage") === "true" || grid.getAttribute("data-crm-record-type") === "deal") {
      add("set_stage", labels(grid, "set_stage", "Set stage"), function () {
        var value = promptValue(grid, "stage", "Stage id");
        if (value !== null) performBulk(grid, table, row, "set_stage", value);
      });
    }
    if (!menu.children.length) return;
    var host = grid.closest(".crm") || document.body;
    host.appendChild(menu);
    var rect = grid.getBoundingClientRect();
    var left = event.clientX || rect.left + 10;
    var top = event.clientY || rect.top + 10;
    menu.style.left = Math.max(0, left) + "px";
    menu.style.top = Math.max(0, top) + "px";
    menu.focus();
    setTimeout(function () {
      document.addEventListener("click", removeMenu, { once: true });
    }, 0);
  };

  var initGrid = function (grid) {
    if (!window.Tabulator || grid.__crmTable) return;
    var rows = parseJson(grid.getAttribute("data-crm-rows"), []);
    var columns = parseJson(grid.getAttribute("data-crm-columns"), []);
    if (!Array.isArray(columns)) columns = [];
    var table = new window.Tabulator(grid, {
      data: Array.isArray(rows) ? rows : [],
      columns: columns,
      layout: grid.getAttribute("data-crm-layout") || "fitDataStretch",
      responsiveLayout: false,
      selectable: true,
      placeholder: grid.getAttribute("data-crm-placeholder") || ""
    });
    grid.__crmTable = table;
    table.on("cellEdited", function (cell) { editCell(grid, cell); });
    table.on("rowContextmenu", function (event, row) {
      event.preventDefault();
      contextMenu(grid, table, event, row);
      return false;
    });
    grid.querySelectorAll("[data-crm-bulk-action]").forEach(function (button) {
      button.addEventListener("click", function () {
        var action = button.getAttribute("data-crm-bulk-action");
        var value = button.getAttribute("data-crm-value");
        performBulk(grid, table, null, action, value === null ? undefined : value);
      });
    });
  };

  var replaceHtml = function (current, html) {
    if (!current || !html) return null;
    var wrapper = document.createElement("div");
    wrapper.innerHTML = html;
    var replacement = wrapper.firstElementChild;
    if (replacement) {
      current.replaceWith(replacement);
      return replacement;
    }
    return null;
  };

  var revertCard = function (item, from, oldIndex) {
    if (!item || !from) return;
    var cards = Array.prototype.filter.call(from.children, function (child) {
      return child.matches("[data-crm-card], .crm-deal-card[data-deal-id]");
    });
    var reference = cards[oldIndex];
    if (reference) from.insertBefore(item, reference);
    else from.appendChild(item);
  };

  var initBoard = function (board) {
    if (!window.Sortable || board.__crmBoard) return;
    var columns = board.querySelectorAll("[data-crm-column], .crm-board-cards[data-stage-id]");
    if (!columns.length) return;
    board.__crmBoard = true;
    Array.prototype.forEach.call(columns, function (column) {
      new window.Sortable(column, {
        group: column.getAttribute("data-crm-group") || "crm-deals",
        animation: 120,
        draggable: "[data-crm-card], .crm-deal-card[data-deal-id]",
        filter: "[data-crm-column-footer], .crm-board-footer",
        onEnd: function (event) {
          var item = event.item;
          var from = event.from;
          var stageId = column.getAttribute("data-crm-stage-id") || column.getAttribute("data-stage-id") || column.dataset.stageId;
          var moveUrl = item.getAttribute("data-crm-move-url") || item.getAttribute("data-move-url") || column.getAttribute("data-crm-move-url") || board.getAttribute("data-crm-move-url");
          moveUrl = expandUrl(moveUrl, item.getAttribute("data-crm-id") || item.getAttribute("data-id") || item.getAttribute("data-deal-id"));
          if (!moveUrl || !stageId) return;
          var data = item.__crmData || {};
          var lockVersion = item.getAttribute("data-crm-lock-version") || item.getAttribute("data-lock-version") || data.lock_version;
          requestJson(moveUrl, "PUT", { stage_id: stageId, lock_version: lockVersion }).then(function (payload) {
            var response = recordFromResponse(payload);
            if (response && response.lock_version !== undefined) item.setAttribute("data-crm-lock-version", response.lock_version);
            var cardHtml = payload && (payload.card_html || payload.card);
            if (cardHtml) item = replaceHtml(item, cardHtml) || item;
            var footer = column.querySelector("[data-crm-column-footer], .crm-board-footer");
            var footerHtml = payload && (payload.footer_html || payload.footer);
            if (footer && footerHtml) replaceHtml(footer, footerHtml);
          }).catch(function (error) {
            revertCard(item, from, event.oldIndex);
            board.classList.add("crm-board-error");
            board.setAttribute("data-crm-error", errorMessage(error.payload, error.message));
          });
        }
      });
    });
  };

  var closeOverlays = function () {
    document.querySelectorAll("[data-crm-overlay], .crm-overlay, .crm-modal").forEach(function (overlay) {
      if (typeof overlay.close === "function") overlay.close();
      else overlay.hidden = true;
      overlay.classList.remove("is-open");
    });
    removeMenu();
  };

  var navigationUrl = function (key) {
    var body = document.body;
    var attr = "data-crm-" + key + "-url";
    return body.getAttribute(attr) || "/crm/" + key;
  };

  var newUrl = function () {
    var body = document.body;
    var current = document.querySelector("[data-crm-new-url]");
    if (current) return current.getAttribute("data-crm-new-url");
    var path = window.location.pathname;
    if (path.indexOf("/crm/accounts") === 0) return "/crm/accounts/new";
    if (path.indexOf("/crm/contacts") === 0) return "/crm/contacts/new";
    if (path.indexOf("/crm/deals") === 0) return "/crm/deals/new";
    if (path.indexOf("/crm/activities") === 0) return "/crm/activities/new";
    return body.getAttribute("data-crm-new-url") || "/crm/accounts/new";
  };

  var initKeyboard = function () {
    if (document.documentElement.hasAttribute("data-crm-keyboard-bound")) return;
    document.documentElement.setAttribute("data-crm-keyboard-bound", "true");
    var pending = null;
    var pendingTimer = null;
    var typing = function (target) {
      if (!target || !target.tagName) return !!(target && target.isContentEditable);
      return /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable;
    };
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        closeOverlays();
        return;
      }
      if (typing(event.target) || event.metaKey || event.ctrlKey || event.altKey) return;
      var key = event.key.toLowerCase();
      if (pending === "g") {
        pending = null;
        clearTimeout(pendingTimer);
        if (key === "a" || key === "c" || key === "d") {
          event.preventDefault();
          window.location.assign(navigationUrl({ a: "accounts", c: "contacts", d: "deals" }[key]));
        }
        return;
      }
      if (key === "g") {
        pending = "g";
        pendingTimer = setTimeout(function () { pending = null; }, 900);
        return;
      }
      if (key === "/") {
        var search = document.querySelector("#q");
        if (search) {
          event.preventDefault();
          search.focus();
          if (typeof search.select === "function") search.select();
        }
      } else if (key === "n") {
        event.preventDefault();
        window.location.assign(newUrl());
      }
    });
  };

  var initMergePicker = function (form) {
    if (form.__crmMergePicker) return;
    form.__crmMergePicker = true;
    var input = form.querySelector("[data-crm-merge-search]");
    var targetInput = form.querySelector("[data-crm-merge-target-id]");
    var results = form.querySelector("[data-crm-picker-results]");
    var selected = form.querySelector("[data-crm-selected-target]");
    var submit = form.querySelector("[data-crm-merge-submit]");
    if (!input || !targetInput || !results) return;
    var timer = null;
    var sourceId = form.getAttribute("data-crm-source-id");
    var searchUrl = form.getAttribute("data-crm-search-url");
    var renderResults = function (items) {
      results.replaceChildren();
      items.forEach(function (item) {
        if (!item.id || String(item.id) === String(sourceId)) return;
        var option = document.createElement("button");
        option.type = "button";
        option.className = "crm-merge-result";
        option.setAttribute("role", "option");
        option.dataset.crmTargetId = item.id;
        option.textContent = item.label || item.name || String(item.id);
        option.addEventListener("click", function () {
          targetInput.value = item.id;
          if (selected) selected.textContent = option.textContent;
          if (submit) submit.disabled = false;
          results.replaceChildren();
          input.value = option.textContent;
        });
        results.appendChild(option);
      });
    };
    var extractResults = function (payload) {
      if (Array.isArray(payload)) return payload;
      if (payload && Array.isArray(payload.records)) return payload.records;
      if (payload && Array.isArray(payload.rows)) return payload.rows;
      if (typeof payload !== "string") return [];
      var doc = new DOMParser().parseFromString(payload, "text/html");
      var found = [];
      doc.querySelectorAll("[data-crm-picker-option], a[href]").forEach(function (node) {
        var href = node.getAttribute("href") || "";
        var match = href.match(/\/crm\/(accounts|contacts)\/(\d+)/);
        if (!match) return;
        found.push({ id: match[2], label: node.textContent.trim() });
      });
      return found.filter(function (item, index, all) {
        return all.findIndex(function (other) { return String(other.id) === String(item.id); }) === index;
      });
    };
    input.addEventListener("input", function () {
      targetInput.value = "";
      if (selected) selected.textContent = "";
      if (submit) submit.disabled = true;
      clearTimeout(timer);
      var query = input.value.trim();
      if (!query || !searchUrl) {
        results.replaceChildren();
        return;
      }
      timer = setTimeout(function () {
        var url = new URL(searchUrl, window.location.origin);
        fetch(url.toString(), { credentials: "same-origin", headers: { "Accept": "text/html, application/json" } })
          .then(function (response) { return response.text(); })
          .then(function (text) {
            var parsed = parseJson(text, null);
            renderResults(extractResults(parsed || text));
          })
          .catch(function () { results.replaceChildren(); });
      }, 180);
    });
  };

  var vendorUrl = function (file, element) {
    var explicit = element && element.getAttribute("data-crm-" + file.replace(".js", "") + "-src");
    if (explicit) return explicit;
    var source = document.querySelector('script[src*="crm.js"]');
    if (source) {
      var sourceUrl = source.src.replace(/\/javascripts\/crm\.js(?:\?.*)?$/, "/" + file);
      if (sourceUrl !== source.src) return sourceUrl;
      return source.src.replace(/crm\.js(?:\?.*)?$/, file);
    }
    return "/assets/plugin_assets/redmine_crm/" + file;
  };

  var ensureVendor = function (globalName, file, element, callback) {
    if (window[globalName]) {
      callback();
      return;
    }
    var script = document.querySelector('script[data-crm-vendor="' + file + '"]');
    if (!script) {
      script = document.createElement("script");
      script.async = false;
      script.dataset.crmVendor = file;
      script.src = vendorUrl(file, element);
      document.head.appendChild(script);
    }
    script.addEventListener("load", callback, { once: true });
  };

  var init = function () {
    document.body.classList.add("crm");
    var grids = document.querySelectorAll("[data-crm-grid], .crm-grid[data-crm-rows][data-crm-columns]");
    var boards = document.querySelectorAll("[data-crm-board], .crm-board");
    var gridElement = grids.length ? grids[0] : null;
    var boardElement = boards.length ? boards[0] : null;
    var startGrids = function () { grids.forEach(initGrid); };
    var startBoards = function () { boards.forEach(initBoard); };
    if (grids.length && !window.Tabulator) ensureVendor("Tabulator", "tabulator.js", gridElement, startGrids);
    else startGrids();
    if (boards.length && !window.Sortable) ensureVendor("Sortable", "sortable.js", boardElement, startBoards);
    else startBoards();
    document.querySelectorAll("form[data-crm-merge-picker]").forEach(initMergePicker);
    initKeyboard();
  };

  window.RedmineCrm = window.RedmineCrm || {};
  window.RedmineCrm.init = init;
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
}());
