# frozen_string_literal: true

class CrmAccountCustomField < CustomField
  def self.customized_class
    CrmAccount
  end

  def self.visible(user=User.current)
    user && user.admin? ? all : where(:visible => true)
  end

  def type_name
    :label_crm_account_plural
  end

  def visible_by?(_project, user=User.current)
    !!(visible? || (user && user.admin?))
  end

  def visibility_by_project_condition(_project_key=nil, _user=User.current, _id_column=nil)
    '1=1'
  end

  def safe_attribute_names(user=nil)
    super(user).reject {|name| name.to_s == 'role_ids'}
  end
end
