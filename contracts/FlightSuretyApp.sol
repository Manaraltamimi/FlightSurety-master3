pragma solidity >=0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./FlightSuretyData.sol";
/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)
using SafeMath for uint8;
    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    uint256 private constant AIRLINES_THRESHOLD = 4;
    uint256 public constant MAX_INSURANCE_COST = 1 ether;
    uint256 public constant INSURANCE_RETURN_PERCENTAGE = 150;
    uint256 public constant MINIMUM_FUND = 10 ether;
    uint8 public airlinesRegisteredCount = 1;
    address private contractOwner;          // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }

mapping(bytes32 => Flight) private flights;
FlightSuretyData flightSuretyData;
mapping(address => mapping(address => bool)) private airlinePolls;
mapping(address => uint256) private airlineVotesCount;

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
         // Modify to call data contract's status
         require(flightSuretyData.isOperational(), "Data contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }


       /// @dev Modifier that requires the "ContractOwner" account to be the function caller
        modifier requireContractOwner()
        {
            require(msg.sender == contractOwner, "Caller is not contract owner");
            _;
        }
        modifier requireCallerAirlineRegistered()
        {

      require(flightSuretyData.isAirlineRegistered(msg.sender), "Airline not registered");
      _;
    }





        /// @dev Modifier that checks if airline address has registered
        modifier requireAirlineRegistered(address airlineAddress) {
            require(flightSuretyData.isAirlineRegistered(airlineAddress), "Airline not registered, or has been funded allready");
            _;
        }
        modifier requireNotAirlineRegistered(address airlineAddress) {
            require(!flightSuretyData.isAirlineRegistered(airlineAddress), "Airline not registered, or has been funded allready");
            _;
        }
        modifier requireCallerAirlineDepositFunds()
        {
        bool funded = false;
        uint funds = flightSuretyData.getAirlineFunds(msg.sender);
        if(funds >= MINIMUM_FUND)
            funded = true;

        require(funded == true, "Airline can not participate in contract until it submits 10 ether");
        _;
      }
      modifier requireTimestampValid(uint timestamp)
      {
         uint currentTime = block.timestamp;
         require(timestamp >= currentTime,"Timetstamp is not valid");
          _;
    }




    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor
                                (
                                  address dataContract
                                )
                                public
    {
        contractOwner = msg.sender;
        flightSuretyData =FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational()
                            public
                            view
                            returns(bool)
    {
        return flightSuretyData.isOperational();  // Modify to call data contract's status
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/


   /**
    * @dev Add an airline to the registration queue
    *
    */
    function registerAirline
                            (
                              address airline
                            )
                            external

                            requireIsOperational
                            requireCallerAirlineRegistered
                            requireNotAirlineRegistered(airline)
                            requireCallerAirlineDepositFunds
                            returns(bool success, uint256 votes)
    {
      require(airline != address(0),"aireline must be a valid");
      success = false;
      votes = 0;

      if(airlinesRegisteredCount < AIRLINES_THRESHOLD) {
              success = flightSuretyData.registerAirline(airline);
              if(success) {
                  airlinesRegisteredCount ++;
              }
          }
          else{
            mapping(address=>bool) supportingAirlines = airlinePolls[airline];
                //check if the airline is not calling 2nd time
                  if(!supportingAirlines[msg.sender])
                   {
                      airlinePolls[airline][msg.sender] = true; //add the sender to the list of voters for the airline
                      airlineVotesCount[airline]++;
                      if(airlineVotesCount[airline] >= airlinesRegisteredCount.div(2))
                      {
                          success = flightSuretyData.registerAirline(airline);
                          votes = airlineVotesCount[airline];
                           if(success) {
                              airlinesRegisteredCount ++;
                               }
                      }
                   }
                }        return (success, votes);
    }


   /**
    * @dev Register a future flight for insuring.
    *
    */
    function registerFlight
                                (
                                  address airline,
                                  string flight,
                                  uint timestamp
                                )
                                external
                                payable
                                requireIsOperational
                                requireAirlineRegistered(airline)
                                requireTimestampValid(timestamp)

    {
      require(msg.value <= MAX_INSURANCE_COST, "Insurance fee must be less than 1 ether");
       //check if the passenger already has insurance

        address(flightSuretyData).transfer(msg.value);

        flightSuretyData.buy(airline, flight, timestamp,msg.sender, msg.value);
    }

   /**
    * @dev Called after oracle has updated flight status
    *
    */
    function processFlightStatus
                                (
                                    address airline,
                                    string memory flight,
                                    uint256 timestamp,
                                    uint8 statusCode
                                )
                                internal
                                requireIsOperational
    {
      if(statusCode == STATUS_CODE_LATE_AIRLINE)
      {
        flightSuretyData.creditInsurees(airline, flight, timestamp,15,10);
      }
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus
                        (
                            address airline,
                            string flight,
                            uint256 timestamp
                        )
                        external
                        requireIsOperational
                        requireAirlineRegistered(airline)
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
                                                requester: msg.sender,
                                                isOpen: true
                                            });

        emit OracleRequest(index, airline, flight, timestamp);
    }


// region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
                                                        // This lets us group responses and identify
                                                        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle
                            (
                            )
                            external
                            payable
                            requireIsOperational
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
                                        isRegistered: true,
                                        indexes: indexes
                                    });
    }

    function getMyIndexes
                            (
                            )
                            view
                            external
                            requireIsOperational
                            returns(uint8[3])
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
                        (
                            uint8 index,
                            address airline,
                            string flight,
                            uint256 timestamp,
                            uint8 statusCode
                        )
                        external
                        requireIsOperational
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }


    function getFlightKey
                        (
                            address airline,
                            string flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
                            (
                                address account
                            )
                            internal
                            returns(uint8[3])
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while(indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
                            (
                                address account
                            )
                            internal
                            returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;  // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

// endregion
function getExistingAirlines
                            (

                            )
                             public
                             view
                             requireIsOperational
                            returns(address[])
        {
         return flightSuretyData.getAirlines();
        }

        function getAirlineFunds
                            (
                            address airline
                            )
                             public
                             view
                             requireIsOperational
                            returns(uint funds)
        {
         return flightSuretyData.getAirlineFunds(airline);
        }

        function getBalance
                            (

                            )
                            public
                            view
                            requireIsOperational
                            returns(uint funds)
            {
                return flightSuretyData.getPassengerFunds(msg.sender);
            }

            function withdrawFunds
            (
                uint amount
            )
            public
            requireIsOperational
            returns(uint funds)
            {
               uint balance = flightSuretyData.getPassengerFunds(msg.sender);
                require(amount <= balance, "Requested amount exceeds balance");

                return flightSuretyData.withdrawPassengerFunds(amount,msg.sender);
            }

}
