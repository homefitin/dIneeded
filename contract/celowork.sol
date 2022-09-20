// SPDX-License-Identifier: MIT

interface IERC20Token {
    function transfer(address, uint256) external returns (bool);

    function approve(address, uint256) external returns (bool);

    function transferFrom(
        address,
        address,
        uint256
    ) external returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function allowance(address, address) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

pragma solidity >=0.7.0 <0.9.0;

contract CeloWork {
    address payable contractOwner;
    address internal cUsdTokenAddress =
        0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1;

    event ReviewProposal(uint256 time, uint256 indexed index, bool approved);

    //proposal struct
    //proposals represent a prospective worker for a given job listing
    struct Proposal {
        address payable owner;
        string email;
        string proposalBody;
    }

    //job listing status enum
    enum JobListingStatus {
        UNDEFINED,
        AcceptingProposals,
        ActiveProposal,
        PaidProposal
    }

    //job listing struct
    //job listings represent a listing for an available job with a given pay
    //need to add email field
    struct JobListing {
        address payable owner;
        JobListingStatus status;
        string email;
        string name;
        string description;
        uint256 bounty;
        uint256 proposalsLength;
        uint256 activeProposal;
        mapping(uint256 => Proposal) proposals;
    }

    struct Request {
        string reason;
        bool requested;
        bool rejected;
    }

    //job listing mapping and length variable
    mapping(uint256 => JobListing) private jobListings;

    mapping(uint256 => Request) private cancelRequests;
    uint256 private jobListingsLength;

    //function modifier to check that the call came from the job listing's owner
    modifier onlyJobListingOwner(uint256 _index) {
        require(msg.sender == jobListings[_index].owner);
        _;
    }

    // modifier to check if job listing's status matches the required status
    modifier checkStatus(JobListingStatus _status, uint256 _index) {
        require(jobListings[_index].status == _status);
        _;
    }

    constructor() {
        contractOwner = payable(msg.sender);
    }

    /// @dev write job listing
    /// @notice add a job listing to the job listing mapping
    /// @notice the owner of the job listing pays the bounty upfront
    function writeJobListing(
        string calldata _email,
        string calldata _name,
        string calldata _description,
        uint256 _bounty
    ) public payable {
        require(bytes(_email).length > 0, "Empty email");
        require(bytes(_name).length > 0, "Empty name");
        require(bytes(_description).length > 0, "Empty description");

        //append the job listing to the job listing mapping
        JobListing storage _jobListing = jobListings[jobListingsLength++];
        _jobListing.owner = payable(msg.sender);
        _jobListing.status = JobListingStatus.AcceptingProposals;
        _jobListing.email = _email;
        _jobListing.name = _name;
        _jobListing.description = _description;
        _jobListing.bounty = _bounty;

        //require the owner of the job listing to pay the bounty of the job listing to the contract
        require(
            IERC20Token(cUsdTokenAddress).transferFrom(
                payable(msg.sender),
                address(this),
                _bounty
            ),
            "Transfer failed."
        );
    }

    /// @dev read job listing
    //given an index, return the fields of the corresponding job listing
    function readJobListing(uint256 _index)
        public
        view
        returns (
            address payable,
            JobListingStatus,
            string memory,
            string memory,
            string memory,
            uint256,
            uint256
        )
    {
        return (
            jobListings[_index].owner,
            jobListings[_index].status,
            jobListings[_index].email,
            jobListings[_index].name,
            jobListings[_index].description,
            jobListings[_index].bounty,
            jobListings[_index].activeProposal
        );
    }

    /// @dev given a job listing index, add a proposal to the corresponding job listing's proposal mapping
    /// @notice writes a proposal for a job listing
    function writeProposal(
        uint256 _jobListingIndex,
        string calldata _email,
        string calldata _proposalBody
    )
        external
        checkStatus(JobListingStatus.AcceptingProposals, _jobListingIndex)
    {
        jobListings[_jobListingIndex].proposals[
            jobListings[_jobListingIndex].proposalsLength
        ] = Proposal(payable(msg.sender), _email, _proposalBody);

        jobListings[_jobListingIndex].proposalsLength++;
    }

    /// @dev read and return a proposal for a job listing
    //given a job listing index and a proposal index, return the fields of the corresponding proposal
    function readProposal(uint256 _jobListingIndex, uint256 _proposalIndex)
        external
        view
        returns (
            address payable,
            string memory,
            string memory
        )
    {
        return (
            jobListings[_jobListingIndex].proposals[_proposalIndex].owner,
            jobListings[_jobListingIndex].proposals[_proposalIndex].email,
            jobListings[_jobListingIndex].proposals[_proposalIndex].proposalBody
        );
    }

    /**
     *  @dev allow job listings' owners to accept and select a winner in the proposals mapping
     *  @notice given a job listing index and a proposal index, mark the proposal as active
     */
    function selectProposal(uint256 _jobListingIndex, uint256 _proposalIndex)
        external
        onlyJobListingOwner(_jobListingIndex)
        checkStatus(JobListingStatus.AcceptingProposals, _jobListingIndex)
    {
        jobListings[_jobListingIndex].activeProposal = _proposalIndex;
        jobListings[_jobListingIndex].status = JobListingStatus.ActiveProposal;
    }

    /**
     * @dev allow job listings' owners to cancel their job listings
     * @notice a reason needs to be provided
     * @param _reason the reason for cancellation of the job listing
     */
    function requestCancel(uint256 _jobListingIndex, string calldata _reason)
        public
        onlyJobListingOwner(_jobListingIndex)
    {
        // job listings that have already been paid can't be cancelled
        require(
            jobListings[_jobListingIndex].status !=
                JobListingStatus.PaidProposal,
            "This is not an active job listing"
        );
        // requested initialized as true
        // rejected initialized as false
        cancelRequests[_jobListingIndex] = Request(_reason, true, false);
    }

    /**
     * @dev allow the smartcontract's owner to reject or approve a cancel request for a job listing
     * @param _decision a number representing the decision to approve or reject a cancel request.
     * @notice _decision can only be the number zero or one
     */
    function reviewRequest(uint256 _decision, uint256 _jobListingIndex)
        public
        
    {
        // job listings that have already been paid can't be cancelled
        require(
            jobListings[_jobListingIndex].status !=
                JobListingStatus.PaidProposal,
            "This is not an active job listing"
        );
        // The number zero means that the cancel request has been approved
        // THe number one means that the cancel request has been rejected
        require(
            _decision == 0 || _decision == 1,
            "Decisions' indexes available are only zero and one"
        );
        require(contractOwner == msg.sender, "Unauthorized caller");
        // runs only if the cancel request for a job has been approved by the contract's owner/admin
        if (_decision == 0) {
            uint256 returnedAmount = jobListings[_jobListingIndex].bounty;
            address payable to = payable(jobListings[_jobListingIndex].owner);
            delete cancelRequests[_jobListingIndex];
            delete jobListings[_jobListingIndex];
            require(
                IERC20Token(cUsdTokenAddress).transfer(to, returnedAmount),
                "Transfer failed."
            );
            emit ReviewProposal(block.timestamp, _jobListingIndex, true);
        } else {
            cancelRequests[_jobListingIndex].rejected = true;
            emit ReviewProposal(block.timestamp, _jobListingIndex, false);
        }
    }

    /// @dev given a job listing index, pay the corresponding active proposal the bounty of the job listing
    function payProposal(uint256 _jobListingIndex)
        external
        payable
        onlyJobListingOwner(_jobListingIndex)
        checkStatus(JobListingStatus.ActiveProposal, _jobListingIndex)
    {
        jobListings[_jobListingIndex].status = JobListingStatus.PaidProposal;
        require(
            IERC20Token(cUsdTokenAddress).transfer(
                payable(
                    jobListings[_jobListingIndex]
                        .proposals[jobListings[_jobListingIndex].activeProposal]
                        .owner
                ),
                jobListings[_jobListingIndex].bounty
            ),
            "Transfer failed."
        );
    }

    //get job listing mapping length
    //return the length of the job listing mapping
    function getJobListingsLength() public view returns (uint256) {
        return (jobListingsLength);
    }

    /// @dev get proposal mapping length
    /// @return proposalsLength given a job listing index, return the length of the corresponding proposal mapping
    function getProposalsLength(uint256 _jobListingIndex)
        public
        view
        returns (uint256)
    {
        return (jobListings[_jobListingIndex].proposalsLength);
    }
}
