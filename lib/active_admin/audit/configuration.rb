module ActiveAdmin
  module Audit
    class Configuration < ActiveAdmin::ApplicationSettings

      # == User class name
      #
      # Set the name of the class that is used as the AdminUser.
      # Defaults to AdminUser
      #
      register :user_class_name, :admin_user
    end
  end
end
