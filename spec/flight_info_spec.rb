# frozen_string_literal: true

require 'spec_helper'
require_relative '../flight_info'

describe FlightInfo do
  let(:correct_flight_number) { 'FS15' }
  let(:array_with_correct_flight_number) { ['LH1829'] }
  let(:array_with_invalid_flight_number) { ['FS15'] }
  let(:array_with_invalid_format_of_flight_number) { ['784'] }
  let(:correct_flight_numbers) { 'FS15 FQ9578' }
  let(:incorrect_flight_numbers) { 'O15 Z5' }
  let(:api_response_data) do
    {
      'greatCircleDistance' => {
        'km' => 1268.386
      },
      'departure' => {
        'airport' => {
          'icao' => 'LEBB',
          'iata' => 'BIO',
          'municipalityName' => 'Bilbao',
          'location' => {
            'lat' => 43.3011,
            'lon' => -2.910609
          },
          'countryCode' => 'ES'
        }
      },
      'arrival' => {
        'airport' => {
          'icao' => 'EDDM',
          'iata' => 'MUC',
          'municipalityName' => 'Munich',
          'location' => {
            'lat' => 48.3538,
            'lon' => 11.7861
          },
          'countryCode' => 'DE'
        }
      }
    }
  end
  let(:csv_file_with_flight_data) { 'ready_flight_numbers.csv' }

  describe '#add_zero' do
    it 'returns flight number with four digits' do
      expect(subject.add_zero(correct_flight_number)).to eq('FS0015')
    end
  end

  describe '#flight_number_check' do
    context 'with correct flight numbers' do
      it 'returns array of flight numbers' do
        expect(subject.flight_number_check(correct_flight_numbers)).to eq(%w[FS0015 FQ9578])
      end
    end

    context 'with incorrect flight numbers' do
      it 'returns empty array' do
        expect(subject.flight_number_check(incorrect_flight_numbers)).to eq([])
      end
    end
  end

  describe '#flight_api_request' do
    context 'with correct flight number' do
      it 'returns array of arrays with flight data and status code 200' do
        flight_data = VCR.use_cassette('flight_api_request_with_code_200') do
          subject.flight_api_request(array_with_correct_flight_number)
        end
        expect(flight_data[0]).to include('200')
      end
    end

    context 'with invalid flight number' do
      it 'returns array of arrays with status code 204' do
        flight_data = VCR.use_cassette('flight_api_request_with_code_204') do
          subject.flight_api_request(array_with_invalid_flight_number)
        end
        expect(flight_data[0]).to include('204')
      end
    end

    context 'with invalid format of flight number' do
      it 'returns array of arrays with status code 400' do
        flight_data = VCR.use_cassette('flight_api_request_with_code_400') do
          subject.flight_api_request(array_with_invalid_format_of_flight_number)
        end
        expect(flight_data[0]).to include('400')
      end
    end
  end

  describe '#take_data' do
    context 'with data from api response' do
      it 'returns array of needed data from hash' do
        expect(subject.take_data(api_response_data)).to eq([
                                                             { city: 'Bilbao', country: 'ES', iata: 'BIO',
                                                               latitude: 43.3011, longitude: -2.910609 },
                                                             { city: 'Munich', country: 'DE',
                                                               iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
                                                             1268.386
                                                           ])
      end
    end
  end

  describe '#creat_fail_response' do
    context 'with 204 code' do
      it 'returns hash with message "Flight not found"' do
        expect(subject.creat_fail_response('204')).to eq({ distance: 0, error_message: 'Flight not found', route: nil,
                                                           status: 'FAIL' })
      end
    end

    context 'with 400 code' do
      it 'returns hash with message "Flight number has invalid format"' do
        expect(subject.creat_fail_response('400')).to eq({ distance: 0,
                                                           error_message: 'Flight number has invalid format',
                                                           route: nil,
                                                           status: 'FAIL' })
      end
    end

    context 'with 401 code' do
      it 'returns hash with message "unauthorized"' do
        expect(subject.creat_fail_response('401')).to eq({ distance: 0, error_message: 'unauthorized', route: nil,
                                                           status: 'FAIL' })
      end
    end

    context 'with 429 code' do
      it 'returns hash with message "Too Many API Requests"' do
        expect(subject.creat_fail_response('429')).to eq({ distance: 0, error_message: 'Too Many API Requests',
                                                           route: nil, status: 'FAIL' })
      end
    end

    context 'with 500 code' do
      it 'returns hash with message "Server error"' do
        expect(subject.creat_fail_response('500')).to eq({ distance: 0, error_message: 'Server error', route: nil,
                                                           status: 'FAIL' })
      end
    end
  end

  describe '#parse_result' do
    context 'one flight with successful api response' do
      result = {
        route: {
          departure: { city: 'Bilbao',
                       country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 },
          arrival: { city: 'Munich',
                     country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 }
        },
        status: 'OK',
        distance: 1268.386,
        error_message: nil
      }

      it 'returns hash with parsed data' do
        expect(subject.parse_result([[api_response_data]], ['200'])).to eq(result)
      end
    end

    context 'two flights with successful api response' do
      result = {
        route: [
          { arrival: { city: 'Munich', country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
            departure: { city: 'Bilbao', country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 },
            distance: 1268.386 },
          { arrival: { city: 'Munich', country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
            departure: { city: 'Bilbao', country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 },
            distance: 1268.386 }
        ],
        status: 'OK',
        distance: 2536.772,
        error_message: nil
      }

      it 'returns hash with parsed data' do
        expect(subject.parse_result([[api_response_data, api_response_data]], %w[200 200])).to eq(result)
      end
    end

    context 'with fail api response' do
      it 'returns hash with fail massage' do
        expect(subject.parse_result([[]], ['204'])).to eq(
          { distance: 0, error_message: 'Flight not found', route: nil, status: 'FAIL' }
        )
      end
    end
  end

  describe '#get_flight_data' do
    context 'with correct flight number' do
      context 'with one flight' do
        result = {
          route: {
            arrival: { city: 'Munich', country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
            departure: { city: 'Bilbao', country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 }
          },
          distance: 1268.386, error_message: nil, status: 'OK'
        }

        it 'returns flight data' do
          flight_data = VCR.use_cassette('one_flight_api_request_from_main') do
            subject.get_flight_data('LH1829')
          end

          expect(flight_data).to eq(result)
        end
      end

      context 'with two flights' do
        result = {
          route: [{
            arrival: { city: 'Munich', country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
            departure: { city: 'Bilbao', country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 },
            distance: 1268.386
          },
                  {
                    arrival: { city: 'Munich', country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
                    departure: { city: 'Bilbao', country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 },
                    distance: 1268.386
                  }],
          distance: 2536.772, error_message: nil, status: 'OK'
        }

        it 'returns flight data' do
          flight_data = VCR.use_cassette('two_flights_api_request_from_main') do
            subject.get_flight_data('LH1829 LH1829')
          end

          expect(flight_data).to eq(result)
        end
      end
    end

    context 'with incorrect flight number' do
      result = {
        route: nil,
        distance: 0, error_message: 'Flight not found', status: 'FAIL'
      }

      it 'returns hash with error message' do
        flight_data = VCR.use_cassette('incorrect_flight_api_request_from_main') do
          subject.get_flight_data('QQ15')
        end

        expect(flight_data).to eq(result)
      end
    end
  end

  describe '#create_headers' do
    it 'creates csv file with headers' do
      File.new(csv_file_with_flight_data, 'w')
      expect { subject.create_headers }.to change { CSV.readlines(csv_file_with_flight_data).size }.by(1)
    end
  end

  describe '#create_csv' do
    it 'fills csv file with flight data' do
      File.new(csv_file_with_flight_data, 'w')
      flight_data = {
        route: {
          arrival: { city: 'Munich', country: 'DE', iata: 'MUC', latitude: 48.3538, longitude: 11.7861 },
          departure: { city: 'Bilbao', country: 'ES', iata: 'BIO', latitude: 43.3011, longitude: -2.910609 }
        },
        distance: 1268.386, error_message: nil, status: 'OK'
      }

      expect { subject.create_csv(flight_data, 'LH1829', 'LH1829', 1) }.to change {
        CSV.readlines(csv_file_with_flight_data).size}.by(1)
    end
  end
end
