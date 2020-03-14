module Helper
  module Repository
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

    def repository_rsync_base_path
      "packages@packages.red-data-tools.org:public"
    end

    def repository_version
      "2020.3.13"
    end

    def repository_gpg_key_ids
      [
        "50785E2340D629B2B9823F39807C619DF72898CB"
      ]
    end
  end
end
