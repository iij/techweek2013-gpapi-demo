require 'yaml'

class Setting
  def initialize(config_path)
    @config_path = config_path
    load_config(config_path)
  end

  def load_config(config_path)
    @config = YAML.load_file(config_path)
  end

  def client
    @client ||=
      begin
        credential = @config["credentials"]
        opts = { :access_key => credential["access_key"], :secret_key => credential["secret_key"] }
        opts[:endpoint] = @config["endpoint"] if @config["endpoint"]
        IIJ::Sakagura::GP::Client.new(opts)
      end
  end

  def gp_client
    gp_sc = fetch("gp_service_code")
    client.gp(gp_sc)
  end

  def fetch(key)
    @config.fetch(key) { raise ArgumentError, "missing #{key}, please check #{@config_path}" }
  end
end

