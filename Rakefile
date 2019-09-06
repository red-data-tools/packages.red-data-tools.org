# -*- ruby -*-

require_relative "repository-task"

class RedDataToolsRepositoryTask < RepositoryTask
  private
  def repository_name
    "red-data-tools"
  end

  def repository_label
    "Red Data Tools"
  end

  def repository_description
    "Red Data Tools related packages"
  end

  def repository_url
    "https://packages.red-data-tools.org"
  end

  def rsync_base_path
    "packages@packages.red-data-tools.org:public"
  end

  def gpg_uid
    "50785E2340D629B2B9823F39807C619DF72898CB"
  end

  def deb_keyring_version
    "2017.10.01"
  end

  def all_products
    [
      "opencv-glib",
    ]
  end
end

repository_task = RedDataToolsRepositoryTask.new
repository_task.define

desc "Apply the Ansible configurations"
task :deploy do
  sh("ansible-playbook",
     "--inventory-file", "ansible/hosts",
     "ansible/playbook.yml")
end
