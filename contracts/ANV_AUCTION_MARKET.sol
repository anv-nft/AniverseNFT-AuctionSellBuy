pragma solidity ^0.8.0;

import "./access/Ownable.sol";
import "./token/ERC20.sol";
import "./token/ERC721.sol";
import "./address/Address.sol";
import "./string/Strings";



pragma solidity ^0.8.0;

contract AuctionRepository {
    
    // Array with all auctions
    Auction[] public auctions;

    // Mapping from auction index to user bids
    mapping(uint256 => Bid[]) public auctionBids;

    // Mapping from owner to a list of owned auctions
    mapping(address => uint[]) public auctionOwner;

    // Bid struct to hold bidder and amount
    struct Bid {
        address from;
        uint256 amount;
    }

    // Auction struct which holds all the required info
    struct Auction {
        uint256 startPrice;
        address nftContract;
        uint256 tokenId;
        address owner;
        bool active;
        bool finalized;
    }

    IERC20 public erc20Token;
    
    mapping (address => mapping (uint256 => uint)) public auctionIdByTokenIdMap;

    constructor ( IERC20 _erc20Token) public {
        erc20Token = _erc20Token;
    }
    /**
    * @dev Guarantees msg.sender is owner of the given auction
    * @param _auctionId uint ID of the auction to validate its ownership belongs to msg.sender
    */
    modifier isOwner(uint _auctionId) {
        require(auctions[_auctionId].owner == msg.sender);
        _;
    }


    // /**
    // * @dev Disallow payments to this contract directly
    // */
    // function() public{
    //     revert();
    // }

    /**
    * @dev Gets the length of auctions
    * @return uint representing the auction count
    */
    function getCount() public view returns(uint) {
        return auctions.length;
    }

    /**
    * @dev Gets the bid counts of a given auction
    * @param _auctionId uint ID of the auction
    */
    function getBidsCount(uint _auctionId) public view returns(uint) {
        return auctionBids[_auctionId].length;
    }

    /**
    * @dev Gets an array of owned auctions
    * @param _owner address of the auction owner
    */
    function getAuctionsOf(address _owner) public view returns( uint[] memory) {
        uint[] memory ownedAuctions = auctionOwner[_owner];
        return ownedAuctions;
    }

    /**
    * @dev Gets an array of owned auctions
    * @param _auctionId uint of the auction owner
    * @return amount uint256, address of last bidder
    */
    function getCurrentBid(uint _auctionId) public view returns(uint256) {
        uint bidsLength = auctionBids[_auctionId].length;
        // if there are bids refund the last bid
        if( bidsLength > 0 ) {
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];
            return (lastBid.amount);
        }
        return 0;
    }

    /**
    * @dev Gets the total number of auctions owned by an address
    * @param _owner address of the owner
    * @return uint total number of auctions
    */
    function getAuctionsCountOfOwner(address _owner) public view returns(uint) {
        return auctionOwner[_owner].length;
    }


    function getAuctionIdByTokenId(address nftContract, uint256 _tokenId) public view returns(uint) {
        return auctionIdByTokenIdMap[nftContract][_tokenId];
    }
    
   
    function getAuctionById(uint _auctionId) public view returns(
        uint256 startPrice,
        address nftContract,
        uint256 tokenId,
        address owner,
        bool active,
        bool finalized) {

        Auction memory auc = auctions[_auctionId];
        return (
            auc.startPrice, 
            auc.nftContract, 
            auc.tokenId, 
            auc.owner, 
            auc.active, 
            auc.finalized);
    }
    

    function createAuction(address _nftContract, uint256 _tokenId , uint256 _startPrice) public  {
        uint auctionId = auctions.length;
        Auction memory newAuction;
        newAuction.startPrice = _startPrice;
        newAuction.nftContract = _nftContract;
        newAuction.tokenId = _tokenId;
        newAuction.owner = msg.sender;
        newAuction.active = true;
        newAuction.finalized = false;
        
        auctions.push(newAuction);        
        auctionOwner[msg.sender].push(auctionId);
        
        auctionIdByTokenIdMap[_nftContract][_tokenId] = auctionId;
        
        emit AuctionCreated(msg.sender, auctionId);
   
    }


    /**
    * @dev Cancels an ongoing auction by the owner
    * @dev Deed is transfered back to the auction owner
    * @dev Bidder is refunded with the initial amount
    * @param _auctionId uint ID of the created auction
    */
    function cancelAuction(uint _auctionId) internal {
        Auction memory myAuction = auctions[_auctionId];
        uint bidsLength = auctionBids[_auctionId].length;

        // if there are bids refund the last bid
        if( bidsLength > 0 ) {
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];

            require(
                IERC20(erc20Token).transfer(lastBid.from, lastBid.amount),
                "Refund token transfer error."
            );
        }

        // approve and transfer from this contract to auction owner
        // IERC721(erc721Token).safeTransferFrom(myAuction.owner , lastBid.from , myAuction.tokenId);
        
        auctions[_auctionId].active = false;
        emit AuctionCanceled(msg.sender, _auctionId);
    }

    /**
    * @dev Finalized an ended auction
    * @dev The auction should be ended, and there should be at least one bid
    * @dev On success Deed is transfered to bidder and auction owner gets the amount
    * @param _auctionId uint ID of the created auction
    */
    function finalizeAuction(uint _auctionId) public {
        Auction memory myAuction = auctions[_auctionId];
        uint bidsLength = auctionBids[_auctionId].length;

        // if there are no bids cancel
        if(bidsLength == 0) {
            cancelAuction(_auctionId);
        } else {

            // 2. the money goes to the auction owner
            Bid memory lastBid = auctionBids[_auctionId][bidsLength - 1];

            require(
                IERC20(erc20Token).transfer(myAuction.owner, lastBid.amount),
                "Refund token transfer error."
            );
        

            // approve and transfer from this contract to the bid winner 
            IERC721(myAuction.nftContract).safeTransferFrom(myAuction.owner , lastBid.from , myAuction.tokenId);
            
            auctions[_auctionId].active = false;
            auctions[_auctionId].finalized = true;
            emit AuctionFinalized(msg.sender, _auctionId);
        }
    }

    /**
    * @dev Bidder sends bid on an auction
    * @dev Auction should be active and not ended
    * @dev Refund previous bidder if a new bid is valid and placed.
    * @param _auctionId uint ID of the created auction
    */
    function bidOnAuction(uint _auctionId , uint256 anvAmount) public payable {
        uint256 ethAmountSent = msg.value;

        // owner can't bid on their auctions
        Auction memory myAuction = auctions[_auctionId];
        require(myAuction.owner != msg.sender , "Owner can not bid on their auctions");

        // get bid length
        uint bidsLength = auctionBids[_auctionId].length;
        // 
        uint256 lastStartPrice = myAuction.startPrice;
        Bid memory lastBid;

        // there are previous bids
        if( bidsLength > 0 ) {
            lastBid = auctionBids[_auctionId][bidsLength - 1];
            lastStartPrice = lastBid.amount;
        }

        // check if amount is greater than previous amount  
        require (erc20Token.balanceOf(msg.sender) > anvAmount , "Lack of balance ERC20");
        
        require (anvAmount > lastStartPrice , "Lack of balance with lastBidAmount");

        // refund the last bidder
        if( bidsLength > 0 ) {
            require(
                IERC20(erc20Token).transfer(lastBid.from, lastBid.amount),
                "Refund token transfer error."
            );
        }

        // insert bid
         require(
                IERC20(erc20Token).transferFrom(msg.sender, address(this), anvAmount),
                "Refund token transfer error."
            );
        
        
        Bid memory newBid;
        newBid.from = msg.sender;
        newBid.amount = anvAmount;
        auctionBids[_auctionId].push(newBid);
        emit BidSuccess(msg.sender, _auctionId);
    }

    event BidSuccess(address _from, uint _auctionId);

    // AuctionCreated is fired when an auction is created
    event AuctionCreated(address _owner, uint _auctionId);

    // AuctionCanceled is fired when an auction is canceled
    event AuctionCanceled(address _owner, uint _auctionId);

    // AuctionFinalized is fired when an auction is finalized
    event AuctionFinalized(address _owner, uint _auctionId);
}