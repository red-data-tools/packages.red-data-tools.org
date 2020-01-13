require_relative "helper"
require_relative "vendor/apache-arrow/dev/tasks/linux-packages/package-task"

class PackagesRedDataToolsOrgPackageTask < PackageTask
  include Helper::Repository

  def define
    super
    define_release_tasks
  end

  private
  def release(target_namespace)
    base_dir = __send__("#{target_namespace}_dir")
    repositories_dir = "#{base_dir}/repositories"
    sh("rsync",
       "-av",
       "#{repositories_dir}/",
       "packages@packages.red-data-tools.org:public/")
  end

  def define_release_tasks
    [:apt, :yum].each do |target_namespace|
      namespace target_namespace do
        desc "Release #{target_namespace} packages"
        task :release => "#{target_namespace}:build" do
          release(target_namespace) if __send__("enable_#{target_namespace}?")
        end
      end
      task target_namespace => "#{target_namespace}:release"
    end
  end
end
