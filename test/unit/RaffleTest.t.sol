// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {VRFCoordinatorV2Mock} from "../mocks/VRFCoordinatorV2Mock.sol";
import {CreateSubscription} from "../../script/Interactions.s.sol";

contract RaffleTest is StdCheats, Test {
    //Events -> In Foundry tests we have to write and emit the events manually, as in can't be taken from the contract
    event RequestedRaffleWinner(uint256 indexed requestId);
    event RaffleEnter(address indexed player);
    event WinnerPicked(address indexed player);

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint64 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2;
    address link;
    uint256 deployerKey;
    uint256 raffleEntranceFee = 0.1 ether;
    address public PLAYER = makeAddr("player"); //gives ease to declare address -> makeAddr()
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE); //as this is in setUp() so it will be called before every test

        (subscriptionId, gasLane, automationUpdateInterval, callbackGasLimit, vrfCoordinatorV2, link, deployerKey) =
            helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializesInOpenState() public view {
        // here because raffle state Type enum, we used Raffle.RaffleState.OPEN
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /////////////////////////
    // enterRaffle         //
    /////////////////////////

    function testRaffleRevertsWHenYouDontPayEnought() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: raffleEntranceFee}();

        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        // HERE TRUE = Topics(indexed parameter)
        vm.expectEmit(true, false, false, false, address(raffle)); // here address(raffle) is passed bcoz as it is address of the emmiter
        emit RaffleEnter(PLAYER); // here we expect the emit to be PLAYER
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    // raffle.performUpkeep(""); is been called by which address? bcoz PLAYER add can be only used once
    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); // as this function is been called successfully means here raffle is OPEN
        vm.warp(block.timestamp + automationUpdateInterval + 1); // as this function is been called successfully means here raffle is CLOSED
        vm.roll(block.number + 1); // no need of this but still to be more realistic
        raffle.performUpkeep(""); // as this function is been called successfully means here raffle is CALCULATING

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); // this time it will fail because raffle is CALCULATING
    }

    /////////////////////////
    // checkUpkeep         //
    /////////////////////////
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep(""); // empty parameter because we dont use it
        // above bool upkeepNeeded is because checkUpkeep function returns two values, first is bool and second is empty

        // Assert
        assert(!upkeepNeeded); //false
    }

    // why capital Raffle. ?
    function testCheckUpkeepReturnsFalseIfRaffleIsnotOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); // as this function is been called means here raffle is OPEN
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep(""); // as this function is been called means here raffle is CLOSED

        // doubt in this line - why capital Raffle. ? - bcoz it is a calling enum named RaffleState
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // Act
        // DOUBT - WHO IS CALLING THIS FUNCTION??

        // WHY IS HERE BOOL UPKEEDNEEDED IS NEEDED? IT IS BECAUSE WE ARE RETURNING TWO VALUES FROM THE FUNCTION, AND SECOND IS //EMPTY
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING); // while calling enum we need to use real name of contract which here is Raffle
        assert(upkeepNeeded == false); // because raffle is not open as the performUpkeep function is been called
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); // as this function is been called means here raffle is OPEN
        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        //Assert
        assert(!upkeepNeeded); // false BECAUSE bool timePassed = ((block.timestamp - s_lastTimeStamp) < i_interval); MEANS TIME HAS NOT PASSED YET
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public {
        // openState.Open, balance > 0, players.length > 0, timePassed more
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); // as this function is been called means here raffle is OPEN
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /////////////////////////
    // performUpkeep       //
    /////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}(); // as this function is been called means here raffle is OPEN
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act / Assert
        // It doesnt revert -> because we are satisfying the condition of checkUpkeep
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        // we are making this variable because we are not satisfying the condition of checkUpkeep
        // and also because we have to pass them as parameter in the vm.expectRevert()
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector( // abi.encodeWithSelector because we are passing parameters
            Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep(""); // failed because we are not satisfying condition of checkUpkeep
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        // requestId = raffle.getLastRequestId();
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1); // 0 = open, 1 = calculating
    }

    /////////////////////////
    // fulfillRandomWords //
    ////////////////////////

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep() public raffleEntered skipFork {
        // Arrange
        // Act / Assert
        vm.expectRevert("nonexistent request");
        // vm.mockCall could be used here...
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(0, address(raffle));

        vm.expectRevert("nonexistent request");

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(1, address(raffle));
    }

    // Have DOUBT in this function
    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered skipFork {
        address expectedWinner = address(1);

        // Arrange
        uint256 additionalEntrances = 3;
        uint256 startingIndex = 1; // We have starting index be 1 so we can start with address(1) and not address(0)

        for (uint256 i = startingIndex; i < startingIndex + additionalEntrances; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether); // deal 1 eth to the player
            raffle.enterRaffle{value: raffleEntranceFee}();
        }

        uint256 startingTimeStamp = raffle.getLastTimeStamp();
        uint256 startingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1]; // get the requestId from the logs

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = raffleEntranceFee * (additionalEntrances + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == startingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
