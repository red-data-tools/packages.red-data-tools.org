require_relative "helper"
require_relative "vendor/apache-arrow/dev/tasks/linux-packages/package-task"

class PackagesRedDataToolsOrgPackageTask < PackageTask
  include Helper::Repository

  def define
    define_clean_tasks
    super
    define_release_tasks
  end

  private
  def repositories_dir(target_namespace)
    base_dir = __send__("#{target_namespace}_dir")
    "#{base_dir}/repositories"
  end

  def release(target_namespace)
    sh("rsync",
       "-av",
       "#{repositories_dir(target_namespace)}/",
       "packages@packages.red-data-tools.org:public/")
  end

  def define_clean_tasks
    [:apt, :yum].each do |target_namespace|
      namespace target_namespace do
        desc "Clean #{target_namespace} packages"
        task :clean do
          if __send__("enable_#{target_namespace}?")
            rm_rf(repositories_dir(target_namespace))
          end
        end
      end
      task target_namespace => "#{target_namespace}:clean"
    end
  end

  def define_release_tasks
    [:apt, :yum].each do |target_namespace|
      namespace target_namespace do
        desc "Release #{target_namespace} packages"
        task :release do
          release(target_namespace) if __send__("enable_#{target_namespace}?")
        end
      end
      task target_namespace => "#{target_namespace}:release"
    end
  end
end
