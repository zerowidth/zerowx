module ZeroWx

  class NationalWeatherService < Api
    self.base_url = "http://forecast.weather.gov"

    class HourlyForecast

      attr_reader :doc

      def initialize(doc)
        @doc = doc
      end

      def times
        return doc.xpath("/dwml/data/time-layout/start-valid-time").map { |t| Time.parse(t.content) }
      end

      def temp
        unless @temp
          temps = doc.xpath("/dwml/data/parameters/temperature[@type='hourly']/value").map do |temp|
            temp.content.empty? ? nil : temp.content.to_i
          end
          @temp = Map.new times.zip(temps).flatten
        end
        @temp
      end

      def wind
        unless @wind
          winds = doc.xpath("/dwml/data/parameters/wind-speed[@type='sustained']/value").map do |speed|
            speed.content.empty? ? nil : speed.content.to_i
          end
          @wind = Map.new times.zip(winds).flatten
        end
        @wind
      end

      def gust
        unless @gust
          gusts = doc.xpath("/dwml/data/parameters/wind-speed[@type='gust']/value").map do |speed|
            speed.content.empty? ? nil : speed.content.to_i
          end
          @gust = Map.new times.zip(gusts).flatten
        end
        @gust
      end

      def precip
        unless @precip
          precipitation = doc.xpath("/dwml/data/parameters/probability-of-precipitation/value").map do |prob|
            prob.content.empty? || prob.content.to_i == 0 ? nil : prob.content.to_i
          end
          @precip = Map.new times.zip(precipitation).flatten
        end
        @precip
      end

      def cloud_cover
        unless @cloud_cover
          coverage = doc.xpath("/dwml/data/parameters/cloud-amount/value").map do |prob|
            prob.content.empty? || prob.content.to_i == 0 ? nil : prob.content.to_i
          end
          @cloud_cover = Map.new times.zip(coverage).flatten
        end
        @cloud_cover
      end
    end

    class Forecast

      attr_reader :doc

      def initialize(doc)
        @doc = doc
      end

      def text_forecast
        time_layout = doc.xpath("//time-layout").detect { |l| l.xpath("layout-key").first.content =~ /k-p12h-n1\d-\d/ }
        names = time_layout.xpath("start-valid-time").map { |x| x['period-name'] }
        text = doc.xpath("//wordedForecast/text").map { |t| t.content }
        names.zip(text)
      end

    end

    def hourly_forecast
      doc = xml_get "/MapClick.php?lat=40.02690&lon=-105.25100&FcstType=digitalDWML", :cache => 900
      return HourlyForecast.new(doc)
    end

    def forecast
      doc = xml_get "/MapClick.php?lat=40.02690&lon=-105.25100&FcstType=dwml", :cache => 900
      return Forecast.new(doc)
    end

  end

end
