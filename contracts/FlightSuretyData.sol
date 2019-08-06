pragma solidity >=0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false
    mapping (address => bool) private registeredAirlines;
    mapping (address => uint) private fundedAirlines;
    mapping(address => uint256) private authorizedContracts;
    address[] airlines;
    uint public  total = 0;
    mapping(address => uint) private accountBalance;
    mapping(bytes32 =>address[]) private airlineinsurees;
    mapping(address =>mapping(bytes32 => uint)) insuredamount;
    mapping(address => uint) private fundedinsurance;
    mapping(bytes32 =>mapping(address => uint)) insuredpayout;
    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor
                                (
                                  address firstAirline
                                )
                                public
    {
        contractOwner = msg.sender;
        registeredAirlines[firstAirline] = true;
        airlines.push(firstAirline);
    }

    function getAirlineFunds
                            (
                                address airline

                            )
                            external
                            view
                            requireIsOperational
                            requireIsCallerAuthorized
                          //  requireIsCallerAirlineRegistered(airline)
                             returns(uint funds)

    {
        return (fundedAirlines[airline]);
    }

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
        require(operational, "Contract is currently not operational");
        _;  // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }
    modifier requireIsCallerAuthorized()
    {
        require(authorizedContracts[msg.sender] == 1, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isAirlineRegistered(address airline)
                        public
                        view
                        returns (bool)
      {
          return registeredAirlines[airline];
      }
    function isOperational()
                            public
                            view
                            returns(bool)
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus
                            (
                                bool mode
                            )
                            external
                            requireContractOwner
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

   /**
    * @dev Add an airline to the registration queue
    *      Can only be called from FlightSuretyApp contract
    *
    */
    function registerAirline
                            (
                              address airline
                            )
                            external

                            requireIsOperational
                            requireIsCallerAuthorized
                            returns(bool success)

    {
      require(airline != address(0));
        registeredAirlines[airline] = true;
        airlines.push(airline);
        return registeredAirlines[airline];
    }
    function getAirlines()
               external
               view
               returns(address[])


   {
       return airlines;
   }
   function getPassengerFunds(address passenger)
                external
                view
                returns(uint)


    {

        return accountBalance[passenger];
    }
    function withdrawPassengerFunds(uint amount,address passenger)
                                external
                                requireIsOperational
                                requireIsCallerAuthorized
                                returns(uint)
{
    accountBalance[passenger] = accountBalance[passenger] - amount;
    passenger.transfer(amount);

    return accountBalance[passenger];
}
    function fundAirline
                            (
                                address airline,
                                uint amount
                            )
                            external
                            requireIsOperational
                            requireIsCallerAuthorized
                          //  requireIsCallerAirlineRegistered(airline)

    {
        fundedAirlines[airline] += amount;
    }


   /**
    * @dev Buy insurance for a flight
    *
    */
    function buy (address  airline,string flight,uint256 _timestamp,address passenger,uint amount)
                           external
                           requireIsOperational
                           requireIsCallerAuthorized
                          // requireIsCallerAirlineRegistered(airline)
   {

       bytes32 flightkey = getFlightKey(airline,flight,_timestamp);

      // PassengerInsurance memory pinsurance = PassengerInsurance({passenger:_passenger,insuranceamount:amount,payout:0});
       //airlineInsurance[flightkey].push(pinsurance);

       airlineinsurees[flightkey].push(passenger);

       insuredamount[passenger][flightkey]= amount;
       insuredpayout[flightkey][passenger] = 0;
   }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
                                   (
                                       address airline,
                                       string flight,
                                       uint256 timestamp,
                                       uint factor_numerator,
                                       uint factor_denominator

                                   )
                                   external
                                   requireIsOperational
                                   requireIsCallerAuthorized

       {
           //get all the insurees
           bytes32 flightkey = getFlightKey(airline,flight,timestamp);

            address[] storage insurees = airlineinsurees[flightkey];


             for(uint8 i = 0; i < insurees.length; i++) {
                address passenger = insurees[i];
                uint256 payout;
               uint amount = insuredamount[passenger][flightkey];

               //check if already paid
               uint paid = insuredpayout[flightkey][passenger];
               if(paid == 0)
               {
                   payout = amount.mul(factor_numerator).div(factor_denominator);

                   insuredpayout[flightkey][passenger] = payout;
                   accountBalance[passenger] += payout;

               }

           }
       }


    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
                            (   address airline,string flight,uint ts,
                                address passenger,
                                uint payout
                            )
                            external
                            requireIsOperational
                            requireIsCallerAuthorized

    {
        bytes32 flightkey = getFlightKey(airline,flight,ts);
        insuredpayout[flightkey][passenger] = payout;
        accountBalance[passenger] += payout;

        //uint256 prev = accountBalance[customerAddress];
        //accountBalance[customerAddress] = 0;
        //passenger.transfer(payout);
    }
    function getAccountBalance(address passenger)
                                   external
                                   view
                                   requireIsOperational
                                   requireIsCallerAuthorized
                                   returns(uint)
            {
               return accountBalance[passenger];
            }

   /**
    * @dev Initial funding for the insurance. Unless there are too many delayed flights
    *      resulting in insurance payouts, the contract should be self-sustaining
    *
    */
    function fund
                            (
                            )
                            public
                            payable
    {
    }

    function getFlightKey
                        (
                            address airline,
                            string memory flight,
                            uint256 timestamp
                        )
                        pure
                        internal
                        returns(bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function()
                            external
                            payable
    {
        fund();
    }


}
