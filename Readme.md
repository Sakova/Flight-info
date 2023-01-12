# Flight Info

This application is designed for make API requests to get flight information using the flight number.

## Features

- Finding flight data
- CSV file creation with flight information

## How to use

1. Clone this repository: 
    ```shell
    git clone https://github.com/Sakova/Flight-info.git
    ```
2. Then in Flight-info folder run:
    ```shell
    bundle install
    ```
3. Create in the root folder `.env` file and add next line to the file:
    ```dotenv
    RAPID_API_KEY=<HERE_PASTE_YOUR_RAPID_API_KEY>
    ```
4. To run the code, open a terminal and paste:
    ```shell
    irb -r ./flight_info.rb
    ```
5. Then paste next line in open irb console from previous step:
    ```shell
    FlightInfo.new.get_flight_data('<Paste here flight number as string>')
    ```
P.S. Rapid Api Key for this app you can take at [AeroDataBox](https://rapidapi.com/aedbx-aedbx/api/aerodatabox).<br />
P.S.S. If you don't have an account, you first need to register for free.