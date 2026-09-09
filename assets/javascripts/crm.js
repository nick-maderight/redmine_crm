(function () {
  "use strict";

  var csrfToken = function () {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  };

  var expandUrl = function (template, id) {
    if (!template || id === undefined || id === null) return "";
    return template.replace(/:id/g, encodeURIComponent(id));
  };

  var parseResponse = function (response) {
    return response.text().then(function (text) {
      if (!text) return {};
      try {
        return JSON.parse(text);
      } catch (_error) {
        return {};
      }
    });
  };

  var moveDeal = function (url, stageId, lockVersion) {
    return fetch(url, {
      method: "PUT",
      credentials: "same-origin",
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken(),
        "X-Requested-With": "XMLHttpRequest"
      },
      body: JSON.stringify({ stage_id: stageId, lock_version: lockVersion })
    }).then(function (response) {
      return parseResponse(response).then(function (payload) {
        if (!response.ok) {
          var error = new Error("The deal could not be moved.");
          error.status = response.status;
          error.payload = payload;
          throw error;
        }
        return payload;
      });
    });
  };

  var restoreCard = function (item, parent, oldIndex) {
    if (!item || !parent) return;
    var cards = Array.prototype.filter.call(parent.children, function (child) {
      return child.hasAttribute("data-crm-card");
    });
    var reference = cards[oldIndex];
    if (reference) parent.insertBefore(item, reference);
    else parent.appendChild(item);
  };

  var boardError = function (board, message) {
    board.classList.add("crm-board-error");
    board.setAttribute("data-crm-error", message);
    board.setAttribute("aria-label", message);
  };

  var initBoard = function (board) {
    if (!window.Sortable || board.getAttribute("data-crm-initialized") === "true") return;
    var columns = board.querySelectorAll("[data-crm-column]");
    if (!columns.length) return;

    board.setAttribute("data-crm-initialized", "true");
    Array.prototype.forEach.call(columns, function (column) {
      new window.Sortable(column, {
        group: "crm-deals",
        animation: 120,
        draggable: "[data-crm-card]",
        onEnd: function (event) {
          var item = event.item;
          var from = event.from;
          var to = event.to;
          var stageId = to.getAttribute("data-crm-stage-id");
          var dealId = item.getAttribute("data-crm-id") || item.getAttribute("data-deal-id");
          var template = board.getAttribute("data-crm-move-url");
          var moveUrl = expandUrl(template, dealId);
          var lockVersion = item.getAttribute("data-crm-lock-version");

          if (from === to || !stageId || !moveUrl || !dealId) return;

          moveDeal(moveUrl, stageId, lockVersion).then(function (payload) {
            var record = payload && (payload.record || payload.deal || payload);
            if (record && record.lock_version !== undefined && record.lock_version !== null) {
              item.setAttribute("data-crm-lock-version", record.lock_version);
            }
            board.classList.remove("crm-board-error");
            board.removeAttribute("data-crm-error");
            board.removeAttribute("aria-label");
          }).catch(function (error) {
            restoreCard(item, from, event.oldIndex);
            boardError(board, error.payload && (error.payload.error || error.payload.message) || error.message);
          });
        }
      });
    });
  };

  var isTyping = function (target) {
    if (!target || !target.tagName) return !!(target && target.isContentEditable);
    return /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName) || target.isContentEditable;
  };

  var closeOverlays = function () {
    document.querySelectorAll("dialog[open]").forEach(function (dialog) {
      if (typeof dialog.close === "function") dialog.close();
      else dialog.removeAttribute("open");
    });
    document.querySelectorAll("[data-crm-overlay].is-open, .crm-overlay.is-open, .crm-modal.is-open").forEach(function (overlay) {
      overlay.classList.remove("is-open");
      overlay.hidden = true;
    });
  };

  var navigationUrl = function (key) {
    var body = document.body;
    var attr = body && body.getAttribute("data-crm-" + key + "-url");
    return attr || "/crm/" + key;
  };

  var newUrl = function () {
    var body = document.body;
    var explicit = body && body.getAttribute("data-crm-new-url");
    if (explicit) return explicit;
    var path = window.location.pathname;
    if (path.indexOf("/crm/accounts") === 0) return "/crm/accounts/new";
    if (path.indexOf("/crm/contacts") === 0) return "/crm/contacts/new";
    if (path.indexOf("/crm/deals") === 0) return "/crm/deals/new";
    if (path.indexOf("/crm/activities") === 0) return "/crm/activities/new";
    return "#crm-new-lead";
  };

  var focusNewLead = function () {
    var target = document.querySelector("#crm-new-lead");
    if (!target) return false;
    if (window.location.hash !== "#crm-new-lead") window.location.hash = "crm-new-lead";
    var field = target.querySelector("input, textarea, select");
    if (field) field.focus();
    return true;
  };

  var initKeyboard = function () {
    if (document.documentElement.getAttribute("data-crm-keyboard-bound") === "true") return;
    document.documentElement.setAttribute("data-crm-keyboard-bound", "true");
    var pending = false;
    var pendingTimer = null;

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        pending = false;
        clearTimeout(pendingTimer);
        closeOverlays();
        return;
      }
      if (isTyping(event.target) || event.metaKey || event.ctrlKey || event.altKey) return;

      var key = event.key.toLowerCase();
      if (pending) {
        pending = false;
        clearTimeout(pendingTimer);
        if (key === "a" || key === "c" || key === "d") {
          event.preventDefault();
          window.location.assign(navigationUrl({ a: "accounts", c: "contacts", d: "deals" }[key]));
        }
        return;
      }
      if (key === "g") {
        pending = true;
        pendingTimer = setTimeout(function () { pending = false; }, 800);
        return;
      }
      if (key === "/") {
        var search = document.querySelector("#q, input[name='q'], .js-search-input");
        if (search) {
          event.preventDefault();
          search.focus();
          if (typeof search.select === "function") search.select();
        }
      } else if (key === "n") {
        event.preventDefault();
        var path = newUrl();
        if (path === "#crm-new-lead" && focusNewLead()) return;
        window.location.assign(path);
      }
    });
  };

  var init = function () {
    document.body.classList.add("crm");
    document.querySelectorAll("[data-crm-board], .crm-board").forEach(initBoard);
    initKeyboard();
  };

  window.RedmineCrm = window.RedmineCrm || {};
  window.RedmineCrm.init = init;
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
}());
