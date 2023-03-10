require 'csv'
require 'uri'
require 'net/http'
require 'openssl'
require 'json'
require 'dotenv/load'

RESPONSE_STATUSES = { '200' => 'OK', '204' => 'Flight not found', '400' => 'Flight number has invalid format',
                      '401' => 'unauthorized', '429' => 'Too Many API Requests', '500' => 'Server error',
                      '598' => 'Read Timeout Error' }.freeze
CSV_FILE_WITH_FLIGHT_NUMBERS = 'flight_numbers.csv'.freeze
CSV_FILE_FOR_DATA_RECORDING = 'ready_flight_numbers.csv'.freeze
AMOUNT_MAX_API_RETRIES = 4

module FlightCSV
  def write_to_csv(csv_line)
    CSV.open(CSV_FILE_FOR_DATA_RECORDING, 'ab') do |line|
      line << csv_line
    end
  end

  def create_headers
    write_to_csv(['Example flight number', 'Flight number used for lookup', 'Lookup status', 'Number of legs',
                  'First leg departure airport IATA', 'Last leg arrival airport IATA', 'Distance in kilometers'])
  end

  def parse_csv(file)
    file_data = CSV.read(file)
    create_headers
    file_data[1..].flatten.each { |flight| get_flight_data(flight) }
  end

  def create_csv(hash, flight_number, number_for_lookup, legs_number)
    if hash[:status] == 'OK'
      d_iata, a_iata = ''

      if legs_number > 1
        d_iata = hash[:route][0][:departure][:iata] || hash[:route][0][:departure][:icao]
        a_iata = hash[:route][-1][:arrival][:iata] || hash[:route][-1][:arrival][:icao]
      else
        d_iata = hash[:route][:departure][:iata] || hash[:route][:departure][:icao]
        a_iata = hash[:route][:arrival][:iata] || hash[:route][:arrival][:icao]
      end

      write_to_csv([flight_number, number_for_lookup, 'OK', legs_number, d_iata, a_iata, hash[:distance]])
    else
      write_to_csv([flight_number, number_for_lookup, 'FAIL', '-', '-', '-', hash[:distance]])
    end
  end
end

class FlightInfo
  include FlightCSV

  def add_zero(flight_number)
    divided_number = flight_number.scan(/([A-Z]{2,3})(\d{1,4})/).flatten
    divided_number[1] = '0' << divided_number[1] until divided_number[1].length == 4
    divided_number.join
  end

  def flight_number_check(flight_number)
    flight_array = flight_number.scan(/[A-Z]{2,3}\d{1,4}/)

    if !flight_array.empty?
      flight_array.map { |flight| flight.count('0-9') == 4 ? flight : add_zero(flight) }
    else
      []
    end
  end

  def flight_api_request(flight_number)
    flight_number.reduce([]) do |array, number|
      url = URI("https://aerodatabox.p.rapidapi.com/flights/number/#{number}")

      http = Net::HTTP.new(url.host, url.port)
      http.read_timeout = 10
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Get.new(url)
      request['X-RapidAPI-Key'] = ENV['RAPID_API_KEY']
      request['X-RapidAPI-Host'] = 'aerodatabox.p.rapidapi.com'

      response = begin
        attempts ||= 1
        http.request(request)
      rescue Net::ReadTimeout
        if (attempts += 1) <= AMOUNT_MAX_API_RETRIES
          sleep(1)
          retry
        else
          { code: '598' }
        end
      end

      response_code = response.is_a?(Hash) ? response[:code] : response.code

      data = response_code == '200' ? JSON.parse(response.read_body).push(response.code) : ['empty', response_code]
      array << data
    end
  end

  def take_data_from_hash(data)
    hash = {}

    iata = data['iata']
    icao = data['icao']
    name = iata ? :iata : :icao
    hash[name] = iata || icao
    hash[:city] = data&.dig('municipalityName') || '-'
    hash[:country] = data&.dig('countryCode') || '-'
    hash[:latitude] = data&.dig('location', 'lat') || '-'
    hash[:longitude] = data&.dig('location', 'lon') || '-'
    hash
  end

  def take_data(hash)
    departure_data = hash['departure']['airport']
    arrival_data = hash['arrival']['airport']

    departure = take_data_from_hash(departure_data)
    arrival = take_data_from_hash(arrival_data)

    distance = hash&.dig('greatCircleDistance', 'km') || 0

    [departure, arrival, distance]
  end

  def creat_fail_response(code)
    message = RESPONSE_STATUSES[code]

    {
      route: nil,
      status: 'FAIL',
      distance: 0,
      error_message: message
    }
  end

  def parse_result(api_response, status_code)
    array = api_response.flatten(1)
    status = 'OK'
    error_message = nil

    if status_code.length == 1
      return creat_fail_response(status_code[0]) if status_code[0] != '200'

      departure, arrival, distance = take_data(array[0])

      {
        route: {
          departure: { **departure },
          arrival: { **arrival }
        },
        status: 'OK',
        distance: distance,
        error_message: nil
      }
    else
      route = array.each_with_index.reduce([]) do |route, (_flight, index)|
        if status_code[index] == '200'
          departure, arrival, distance = take_data(array[index])
          route << { departure: departure, arrival: arrival, distance: distance }
        else
          status = 'FAIL'
          error_message = RESPONSE_STATUSES[status_code[0]]
          route << { departure: '-', arrival: '-', distance: 0 }
        end
      end

      full_distance = route.reduce(0) { |full_distance, distance| full_distance + distance[:distance] }

      {
        route: route,
        status: status,
        distance: full_distance,
        error_message: error_message
      }
    end
  end

  def get_flight_data(flight_number)
    check_result = flight_number_check(flight_number)
    return { route: nil, status: 'FAIL', distance: 0, error_message: 'Invalid flight number' } if check_result.empty?

    request = flight_api_request(check_result)
    statuses_code = request.reduce([]) { |statuses, flight| statuses << flight.pop }
    parse_result(request, statuses_code)

    # create_csv(parse_result, flight_number, check_result.join(" "), statuses_code.length)  # For filling csv file data
  end
end
