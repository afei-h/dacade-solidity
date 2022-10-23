import "@openzeppelin/contracts/access/Ownable.sol";

// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0 <0.9.0;

/**
 * @title Bounty contract
 * @notice This contract allows users to post bounties or apply for a bounty.
 */
contract Bounties is Ownable{

    /// @notice Public Variable to store the compensation ratio (default 20%)
    /// @dev 1/compensationRate of the total bounty reward will be used as compensation for applicants. could be modified by contract owner
    uint256 public compensationRate = 5;

    /// @notice Public variable to look up the bounties through the hashvalue of the bounty content
    /// @dev mapping from hashvalue of the bounty content address bounty states
    mapping (bytes32 => Bounty) public bounties;

    /// @notice Public variable to look up who is working on the bounties
    /// @dev mapping from hashvalue of applicants
    mapping (bytes32 => address[]) public applicants;

    /// @notice Public variable to look up is sombody an applicant of the bounty
    /// @dev mapping from address to a mapping which maps from bountyHash to a bool value
    mapping (address => mapping(bytes32 => bool)) public isApplicant;


    /// @notice a data structure to state of a bounty
    /// @dev only the hash value of the bounty content is stored in this struct,the full discription will be stored in the event log
    /// @param funder store the address of the creator of this bounty
    /// @param appliers an array to store the addresses of who is working on this bounty
    /// @param expires this bounty is valid only when current blocktimestamp less than expires
    /// @param isSubmitted should be set to true by applicant after he has submitted his solution
    /// @param isAccomplished should be set to true by funder after he has accepted one of the submitions
    struct Bounty{
        address funder;
        uint256 expires;
        uint256 reward;
        bool isSubmitted;
        bool isAccomplished;
    }


    /// @dev prevent reentrant attacks
    bool private locked = false;

    modifier lock() {
        require(locked == false, 'contract locked!');
        locked = true;
        _;
        locked = false;
    }


    modifier onlyFunder(bytes32 _contentHash) {
        require(bounties[_contentHash].funder == msg.sender, "Not funder");
        _;
    }

    modifier notComplete(bytes32 _contentHash) {
        require(!bounties[_contentHash].isAccomplished, "bounty is already completed!");
        _;
    }


    /// @notice this event is emitted when the compensation rate is changed.
    event compensationRateChanged(uint256 newCompensationRate);
    /// @notice this event is emitted when a bounty is created.
    event bountyCreated (bytes32 indexed contentHash, address indexed funder, uint256 expires, uint256 reward, string bountyContent);
    /// @notice this event is emitted when a bounty is applied.
    event bountyApplied (bytes32 indexed contentHash, address indexed funder, address indexed applicant);
    /// @notice this event is emitted when someone submitted a solution.
    event someoneSubmitted (bytes32 indexed contentHash, address indexed applicant);
    /// @notice this event is emitted when a bounty is completed.
    event bountyCompleted (bytes32 indexed contentHash, address indexed funder, address indexed winner);
    /// @notice this event is emitted when a bounty is withdrawed.
    event bountyWithdrawed (bytes32 indexed contentHash, address indexed funder);


    /// @notice Check whether the bounty has been completed
    function isAccomplished(bytes32 _contentHash) public view returns (bool) {
        return bounties[_contentHash].isAccomplished;
    }

    /// @notice Check if someone has provided a solution 
    function isSubmitted(bytes32 _contentHash) public view returns (bool) {
        return bounties[_contentHash].isSubmitted;
    }

    ///@notice chenge the compensation rate(only owner)
    function changeCompensationRate(uint256 _rate) public onlyOwner {
        compensationRate = _rate;
        emit compensationRateChanged(_rate);
    }

    /// @notice post a bounty
    /// @dev the hashvalue of the bounty content is used for index number
    function postBounty (string memory _bountyContent, uint256 _expires) public payable {
        require(msg.value > 0, "You should pay applicants!");
        bytes32 contentHash = keccak256(abi.encodePacked(_bountyContent));
        require(bounties[contentHash].expires == 0, "bounty already created!");

        //msg.sender is passed to Bounty.funder, msg.value is passed to Bounty.reward
        bounties[contentHash] = Bounty(msg.sender, _expires, msg.value, false, false);

        emit bountyCreated(contentHash, msg.sender, _expires, msg.value, _bountyContent);
    } 

    /// @notice apply for a bounty
    /// @dev use hashvalue of the bounty content rather than string to cut gas costs. 
    /// @dev check expires and reward to make sure the applicant is well informed about the details of the bounty
    function applyBounty (bytes32 _contentHash, uint256 _expires, uint256 _reward) public notComplete(_contentHash){
        //Bounty storage bounty = bounties[_contentHash]; => This way would cost more gas.
        require(block.timestamp < bounties[_contentHash].expires, "bounty expired!");
        require(bounties[_contentHash].expires == _expires, "check the expires!");
        require(bounties[_contentHash].reward == _reward, "check the reward!");
        require(bounties[_contentHash].funder != msg.sender, "you can't apply yourself!");

        applicants[_contentHash].push(msg.sender);
        isApplicant[msg.sender][_contentHash] = true;
        emit bountyApplied(_contentHash, bounties[_contentHash].funder, msg.sender);
    }

    /// @notice applicant should call this after submitting solution to the funder
    function submit(bytes32 _contentHash) public {
        require(isApplicant[msg.sender][_contentHash], "only an applicant could call this!");
        bounties[_contentHash].isSubmitted = true;

        emit someoneSubmitted(_contentHash, msg.sender);
    } 

    /// @notice end the bounty, after the funder accepted one of the submitions
    function completeBounty(bytes32 _contentHash, address payable winner) public lock onlyFunder(_contentHash) notComplete(_contentHash){
        require(bounties[_contentHash].isSubmitted, "no one has submit a solution!");
        require(isApplicant[winner][_contentHash], "winner must be an applicant!");

        bounties[_contentHash].isAccomplished = true;
        winner.transfer(bounties[_contentHash].reward);

        emit bountyCompleted(_contentHash, msg.sender, winner);
    }


    /// @notice withdraw the bounty(only by funder)
    function withdrawBounty(bytes32 _contentHash) public lock onlyFunder(_contentHash) notComplete(_contentHash){

        //if withdraw before expirs, funder must compensate all applicants
        uint256 applicantNum = applicants[_contentHash].length;
        if (applicantNum > 0 && block.timestamp < bounties[_contentHash].expires){
            uint256 compensation = bounties[_contentHash].reward / compensationRate / applicantNum;
            for (uint256 i = 0; i < applicantNum; i++){
                bounties[_contentHash].reward -= compensation;
                payable(applicants[_contentHash][i]).transfer(compensation);
            }
        }
        
        //withdraw remaining balance
        bounties[_contentHash].isAccomplished = true;
        payable(msg.sender).transfer(bounties[_contentHash].reward);

        emit bountyWithdrawed(_contentHash, msg.sender);
    }
}