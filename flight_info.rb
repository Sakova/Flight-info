require 'csv'
require 'uri'
require 'net/http'
require 'openssl'
require 'json'

RESPONSE_STATUSES = {"200" => "OK", "204" => "Flight not found", "400" => "The request failed", "401" => "unauthorized", "429" => "Too Many API Requests", "500" => "Server error"}
CSV_FILE_WITH_FLIGHT_NUMBERS = "flight_numbers.csv"

module FlightCSV
  def create_headers
    CSV.open('redy_flight_numbers9.csv','ab') do |hdr|
      hdr << ["Example flight number", "Flight number used for lookup", "Lookup status", "Number of legs", "First leg departure airport IATA", "Last leg arrival airport IATA", "Distance in kilometers"]
    end
  end

  def parse_csv(file)
    file_data = CSV.read(file)
    create_headers
    file_data[1..].flatten.each { |flight| main(flight) }
  end

  def create_csv(hash, flight_number, number_for_lookup, legs_number)
    if hash[:status] == "OK"
      d_iata, a_iata = ""

      if legs_number > 1
        d_iata = hash[:route][0][:departure][:iata] || hash[:route][0][:departure][:icao]
        a_iata = hash[:route][-1][:arrival][:iata] || hash[:route][-1][:arrival][:icao]
      else
        d_iata = hash[:route][:departure][:iata] || hash[:route][:departure][:icao]
        a_iata = hash[:route][:arrival][:iata] || hash[:route][:arrival][:icao]
      end

      CSV.open('redy_flight_numbers9.csv','ab') do |line|
        line << [flight_number, number_for_lookup, "OK", legs_number, d_iata, a_iata, hash[:distance]]
      end
    else
      CSV.open('redy_flight_numbers9.csv','ab') do |line|
        line << [flight_number, number_for_lookup, "FAIL", "-", "-", "-", hash[:distance]]
      end
    end
  end
end

class FlightInfo
  include FlightCSV

  def add_zero(flight_number)
    divided_number = flight_number.scan(/([A-Z]{2,3})(\d{1,4})/).flatten
    until divided_number[1].length == 4 do
      divided_number[1] = "0" << divided_number[1]
    end
    divided_number.join
  end
  
  def flight_number_check(flight_number)
    flight_array = flight_number.scan(/[A-Z]{2,3}\d{1,4}/)
  
    if !flight_array.empty?
      flight_array.map {|flight| flight.count("0-9") == 4 ? flight : add_zero(flight) }
    else
      []
    end
  end
  
  def flight_api_request(flight_number)
    flight_number.reduce([]) do |array, number|
      url = URI("https://aerodatabox.p.rapidapi.com/flights/number/#{number}")
  
      http = Net::HTTP.new(url.host, url.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      
      request = Net::HTTP::Get.new(url)
      request["X-RapidAPI-Key"] = 'a4e7b0ebffmsh280b22419454e16p1febfdjsnc754aa81ea53'
      request["X-RapidAPI-Host"] = 'aerodatabox.p.rapidapi.com'
      
      response = http.request(request)
      response_code = response.code
      data = response_code == "200" ? JSON.parse(response.read_body).push(response.code) : [ "empty", response_code]
      array << data
    end
  end
  
  def take_data(hash)
    departure = {}
    arrival = {}
  
    departure_data = hash["departure"]["airport"]
    arrival_data = hash["arrival"]["airport"]
  
    d_iata = departure_data["iata"]
    d_icao = departure_data["icao"]
    name = d_iata ? :iata : :icao
    departure[name] = d_iata ? d_iata : d_icao
    departure[:city] = departure_data&.dig("municipalityName") || "-"
    departure[:country] = departure_data&.dig("countryCode") || "-"
    departure[:latitude] = departure_data&.dig("location", "lat") || "-"
    departure[:longitude] = departure_data&.dig("location", "lon") || "-"
  
    a_iata = arrival_data["iata"]
    a_icao = arrival_data["icao"]
    name = a_iata ? :iata : :icao
    arrival[name] = d_iata ? a_iata : a_icao
    arrival[:city] = arrival_data&.dig("municipalityName") || "-"
    arrival[:country] = arrival_data&.dig("countryCode") || "-"
    arrival[:latitude] = arrival_data&.dig("location", "lat") || "-"
    arrival[:longitude] = arrival_data&.dig("location", "lon") || "-"
  
    distance = hash&.dig("greatCircleDistance", "km") || 0
  
    return departure, arrival, distance
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
    status = "OK"
    error_message = nil
  
    if status_code.length == 1
      return creat_fail_response(status_code[0]) if status_code[0] != "200"
      departure, arrival, distance = take_data(array[0])
  
      {
        route: {
          departure: {**departure},
          arrival: {**arrival}
        },
        status: 'OK',
        distance: distance,
        error_message: nil
      }
    else
      route = array.each_with_index.reduce([]) do |route, (flight, index)|
        if status_code[index] == "200"
          departure, arrival, distance = take_data(array[index])
          route << {departure: departure, arrival: arrival, distance: distance}
        else
          status = "FAIL"
          error_message = RESPONSE_STATUSES[status_code[0]]
          route << {departure: "-", arrival: "-", distance: 0}
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
  
  def main(flight_number)
    check_result = flight_number_check(flight_number)
    return {route: nil, status: 'FAIL', distance: 0, error_message: "Invalid flight number"} if check_result.empty?
  
    request = flight_api_request(check_result)
    statuses_code = request.reduce([]) { |statuses, flight| statuses << flight.pop }
    parse_result = parse_result(request, statuses_code)

    # create_csv(parse_result, flight_number, check_result.join(" "), statuses_code.length)  # For filling csv file data
    parse_result
  end
end

# FlightInfo.new.parse_csv(CSV_FILE_WITH_FLIGHT_NUMBERS)  # For creating csv file with flight inforation using existing csv file with flight numbers
# FlightInfo.new.main("LH1829") # For searching flight information using flight number in string format
