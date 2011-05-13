module ZeroWx

  class Api
    Error = Class.new(StandardError)

    class << self
      attr_accessor :base_url
      attr_accessor :cache_server
    end

    attr_reader :http

    def initialize
      @http = Patron::Session.new
      http.timeout = 30
      http.base_url = self.class.base_url or raise "no base url!"
    end

    def cache(key, ttl)
      if Api.cache_server
        key = key.gsub(/\W/, "-")
        puts "cache get: #{key}"
        Api.cache_server.fetch(key, ttl) do
          puts "cache set: #{key} - #{ttl}"
          yield
        end
      else
        yield
      end
    end

    def get(url, opts)
      ttl = opts.delete :cache
      return cache url, ttl do
        response = http.get url
        if response.status >= 300
          raise Error, "HTTP #{response.status}\n#{response.body}"
        end
        response.body
      end
    end

    def hash_get(url, opts={})
      response = get url, opts
      doc = Nokogiri::XML.parse(response)
      return hashify(doc)
    end

    def xml_get(url, opts={})
      response = get url, opts
      return Nokogiri::XML.parse(response)
    end

    def csv_get(url, opts={})
      response = get url, opts
      return csv_data(response)
    end

    def hashify(xml)
      h = {}
      if xml.element_children.empty?
        return xml.content
      else
        xml.element_children.each do |child|
          if h[child.name]
            h[child.name] = [h[child.name]] unless h[child.name].kind_of?(Array)
            h[child.name].push hashify(child)
          else
            h[child.name] = hashify child
          end
        end
        return h
      end
    end

    def csv_data(doc)
      data = []
      doc = doc.gsub(/<[^>]+>/, "")
      FasterCSV.parse(doc, :headers => true, :return_headers => false) do |row|
        data << row.to_hash
      end
      return data.reject { |h| h.empty? }
    end

  end

end
