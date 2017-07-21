require "httparty"
require "json"
require "sinatra"

set :bind, '0.0.0.0'

get '/metrics' do
  
  # Get a list of networks
  raw_networks = JSON.parse(HTTParty.get("http://192.168.2.54:9999/api/v1/networks/").body)

  networks = []
  epInfo = {}
  records = []

  raw_networks.each do |block|
    if block["nwType"] != "infra"
      networks << block["key"]
    end
  end

  # Get endpoints and endpoint info for each network
  networks.each do |net|
    raw_epstats = JSON.parse(HTTParty.get("http://192.168.2.54:9999/api/v1/inspect/networks/#{net}/").body)

    tenant = raw_epstats["Config"]["tenantName"]
    network = raw_epstats["Config"]["networkName"]
    endpoints = raw_epstats["Oper"]["endpoints"]

    endpoints.each do |ep|
      endptID = ep["endpointID"]
      host = ep["homingHost"]
      container = ep["containerName"]

      # create hash of endpointID to hash of endpoint info
      epInfo[endptID] = {
        "tenant": tenant,
        "network": network,
        "endpointID": endptID,
        "host": host,
        "containerName": container,
      }
    end
  end

  # get ovs stats
  ovs_output = `ovs-vsctl --db=tcp:127.0.0.1:6640 list interface | egrep "name|external_ids|statistics"`

  # group ovs output by interface
  interfaces = ovs_output.strip.split("\n").each_slice(4)

  interfaces.each do |ex_id, name, stats, status|
    epInfo.keys.each do |key|
      if ex_id.include?(key)
        # get container interface
        epInfo[key]["interface"] = name.split(":").last.gsub("\"", "").strip

        # get stats into hash
        epstats = stats.split(":").last.scan(/(\w+)=(\d+)/).to_h

        #create key-value pairs and store into array
        info = "{" + epInfo[key].map{|k,v| "#{k}=\"#{v}\""}.join(", ") + "}"
        epstats.each do |metric, value|
          records << "#{metric}#{info} #{value}"
        end 
      end
    end
  end

  # return key-value pairs
  records.join("\n") + "\n"
end
