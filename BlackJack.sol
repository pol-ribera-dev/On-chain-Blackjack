// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.24;

/*  
    @title Blackjack Battle Royale

    @author Pol Ribera

    @notice On-chain Blackjack-style game where players draw "random" cards (1–12),
        aim to get as close as possible to 21 without exceeding it. 
        They compete for a global Top 3 leaderboard, with ties favoring lastest players 
        that interact with the contract.

    @dev Scores are tracked per address and incremented on each draw call by a
        "pseudo-random" value in the range [1,12]. Drawing is disabled once a score
        exceeds 21, marking the player as busted. Only non-busted scores are
        eligible for leaderboard comparison. The leaderboard is updated whenever
        a score outperforms or draws existing entries, triggering an event emission.
        Tie-breaking logic prioritizes lastest players that interact with the contract 
        over existing  leaderboard entries. It is possible to have empty values in the 
        bottom of the leaderboard because when a player gets busted, it is deleted from there,
        but his possition will not be replaced until an other player interacts with tha contract.  
*/

contract BlackJack{

    //================================================
    //                DATA STRUCTURES
    //================================================
    
    /// @dev Represents a player with their address and current score. It is used to do the leaderboard.

    struct Player {
        address user;
        uint8 score;
    }

    /// @dev Tracks the current score of each player by their Ethereum address.
    ///     The score represents the accumulated value from the draw function and it is a uint8 
    ///     because it cannot be values over 12 + 21 (33), so with the 8 bits we have enough.

    mapping (address => uint8) private scores;

    /// @dev Represents the actual leaderboard, it stores the 3 newest players with more score. 
    ///     Only 3 players are stored to limit gas costs. The array is always kept sorted in descending 
    ///     order, with `leaderboard[0]` being the player with the highest score.

    Player[3] private leaderboard;
    

    //================================================
    //                  MODIFIERS
    //================================================


    /// @notice Checks that the player has not exceeded 21 before executing the function.
    /// @dev This modifier does not revert the transaction because it is also used in the
    ///     'updateLeaderboard' function. Reverting here would not make sense, as we want
    ///     to modify the player score even if the player has too many points that he can not
    ///     appear on the leaderboard.

    modifier notBusted() {
        if(scores[msg.sender] <= 21){
            _;
        }
    }

    /// @notice Checks that the player has exceeded 21 before executing the function.

    modifier Busted() {
        if(scores[msg.sender] > 21){
            _;
        }
    }
    

    //================================================
    //                   EVENTS
    //================================================

    /// @notice Emitted whenever the top 3 players on the leaderboard are updated.
    /// @param leaderboard An array containing the top 3 players.

    event LeaderboardUpdated(Player[3] leaderboard);

    /// @notice Emitted when a player receives a new card.
    /// @param _player The address of the player who received the card.
    /// @param _card The value of the card that was dealt to the player.

    event RecivedCard(address indexed _player, uint8 _card);

    //================================================
    //              EXTERNAL FUNCTIONS 
    //================================================

    /// @notice Allows a player to draw a card. The player is the account that calls the transaction.
    /// @dev This function can only be called if the player has not busted. It gets a pseudo-random
    ///     number and adds it to the player's score. Then, the leaderboard is updated.
    ///     Emits {RecivedCard} with the player's address and the value of the card.

    function draw() external notBusted {
        uint8 rand = generateRandom();
        scores[msg.sender] += rand;
        updateLeaderboard();
        deleteIfBusted();
        emit RecivedCard (msg.sender, rand);
    }

    /// @notice Updates the leaderboard with the actual value of the adress that call the tx and returns its score.

    function myScore() external returns (uint8) {
        updateLeaderboard();
        return scores[msg.sender];
    }

    /// @notice Updates the leaderboard with the actual value of the adress that call the tx and returns the leaderboard array.
    /// @dev Unlike the automatic getter for the `leaderboard` array, this function returns all 3 players at once.

    function getLeaderboard() external returns (Player[3] memory) {
        updateLeaderboard();
        return leaderboard;
    }

    
        
    //================================================
    //              INTERNAL FUNCTIONS 
    //================================================

    /*
        @notice Generates a pseudo-random number between 1 and 12 (inclusive).
    
        @dev This function is intended for learning and practice purposes only.
            This is my first blockchain project, so I deliberately avoided using
            external randomness providers such as Chainlink VRF.
    
            The generated value is not truly random, as it can be deterministically 
            calculated from publicly available on-chain data. It MUST NOT be used 
            in production or in any scenario requiring security, fairness, or trust.
    
            The randomness is derived by hashing a combination of:
                - block.timestamp
                - msg.sender
                - block.number
        
            This approach provides basic unpredictability and acceptable distribution
            for low-stakes or non-critical logic, while being gas-efficient.
        
            A persistent seed stored in contract storage was intentionally not used,
            as it would not add meaningful security in this context and would increase
            storage costs.
        
        @return rand A pseudo-random uint8 value in the range [1, 12].
    */

    function generateRandom () internal view returns(uint8 rand_) {
        rand_ = uint8(uint(keccak256(abi.encodePacked(block.timestamp, msg.sender,block.number)))% 12 + 1)  ;
    }


    /// @notice Updates the leaderboard: Puts the caller's new score insite the correct place in the leaderboard if it is higher 
    ///     than at least the third-place score and equal or less than the maximum puntuation(21).
    /// @dev The leaderboard is always kept sorted and updated (except for the new value). Busted values (>21) are ignored with the modifier.
    ///    The score is only inserted if it is at least higher than the current third-place score; otherwise, the function exits early to save gas.
    ///    When the new score is inserted, lower-ranking scores are shifted or removed as needed to maintain the array sorted and with just 3 values.
    ///    To prevent the same player from appearing multiple times on the leaderboard with different (or same) scores, a system has been designed 
    ///    knowing that the uploaded score is always equal to or higher than the previous one of the same player. This makes it easy to determine 
    ///    which positions need to be shifted in order to maintain consistency.
    ///    Emits {LeaderboardUpdated} at the end of execution to broadcast the updated leaderboard.

    function updateLeaderboard() internal notBusted {
        uint8 score = scores[msg.sender];
        if (score <= leaderboard[2].score) return;   
        Player memory newTop = Player(msg.sender, score);    
        if (newTop.score >= leaderboard[0].score) {
            if (leaderboard[0].user != msg.sender) {
                if (leaderboard[1].user != msg.sender) {
                    leaderboard[2] = leaderboard[1];
                }
                leaderboard[1] = leaderboard[0];
            }
            leaderboard[0] = newTop;
        } else if (newTop.score >= leaderboard[1].score) {
            if (leaderboard[1].user != msg.sender) {
                leaderboard[2] = leaderboard[1];
            }
            leaderboard[1] = newTop;
        } else {
            leaderboard[2] = newTop;
        }
        emit LeaderboardUpdated(leaderboard);
    } 

    /// @notice Deletes the busted players from the leaderboard
    /// @dev When player is busted, checks one by one the positions of the leaderboard and if he gets found,
    ///     it is replaced with an empty one, shifting all the other positions to the top of the leaderboard.  

    function deleteIfBusted() internal Busted {
        if (leaderboard[0].user == msg.sender) {
            leaderboard[0] = leaderboard[1];
            leaderboard[1] = leaderboard[2];
            delete leaderboard[2];
        }
        else if (leaderboard[1].user == msg.sender) {
            leaderboard[1] = leaderboard[2];
            delete leaderboard[2];
        }
        else if (leaderboard[2].user == msg.sender){
            delete leaderboard[2];
        }
    }
}
