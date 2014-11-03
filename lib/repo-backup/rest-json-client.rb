require 'json'
require 'net/http'

# Very simple REST API client
class RepoBackup
class RestJsonClient
  def initialize(base_uri, headers = {})
    @headers = headers
    @base_uri = base_uri
    @base_uri = URI(@base_uri) unless @base_uri.respond_to?(:merge)

    # It should close on finalization, good enough for us
    @http = Net::HTTP.new(@base_uri.hostname, @base_uri.port)
    @http.use_ssl = @base_uri.scheme == 'https'
  end

  def get(path, format = :ruby)
    return data(request(:Get, path), format)
  end

private
  # Create an HTTP request
  def request(meth, path)
    uri = @base_uri.merge(path)
    req = Net::HTTP.const_get(meth).new(uri.to_s)
    @headers.each { |k,v| req[k] = v }
    return req
  end

  # Perform an HTTP request, handling redirects
  def do_request(req)
    resp = @http.request(req)
    case resp
    when Net::HTTPRedirection then
      req.uri = resp['location']
      return do_request(req)
    when Net::HTTPSuccess then
      return resp.body
    else
      raise "Failed to fetch #{uri}: #{resp}"
    end
  end

  # Get data from an HTTP request
  def data(req, format = :ruby)
    json = do_request(req)
    return json if format == :json
    return JSON.parse(json)
  end
end
end
