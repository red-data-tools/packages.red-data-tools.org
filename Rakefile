# -*- ruby -*-

desc "Update Apache Arrow packages"
task "apache-arrow" do
  cd("apache-arrow") do
    ruby("-S", "rake", "source", "yum", "apt", "ubuntu")
  end
end

task :default => ["apache-arrow"]
