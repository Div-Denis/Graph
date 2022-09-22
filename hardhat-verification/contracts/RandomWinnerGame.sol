// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract RandomWinnerGame is  VRFConsumerBase, Ownable {
    //Chainlink 变量
    //要与请求一起发送的link数量
    uint256 public fee;
    //生成随机性的公钥的名字ID
    bytes32 public keyHash;

    //玩家地址
    address[] public players;
    //一场比赛最大的玩家人数
    uint8 maxPlayers;
    //表示游戏是否开始的变量
    bool public gameStarted;
    // 进入游戏的费用
    uint256 entryFee;
    //当前游戏ID
    uint256 public gameId;
    
    //当游戏开始时发出
    event GameStarted(uint256 gameId, uint8 maxPlayers, uint256 entryFee);
    //当有人加入游戏时发出
    event PlayerJoined(uint256 gameId, address player);
    //当游戏结束时发出
    event GameEnded(uint256 gameId, address winner, bytes32 requestId);

   /**
    *  构造函数继承一个VRFConsumerBase并初始化keyHash、fee和gameStarted的值
    * @param vrfCoordinator  VRFCoordinator合约地址
    * @param linkToken link代币的合约地址，它是chainlink接受付款的代币
    * @param vrfFee 发送随机请求所需的Link代币数量
    * @param vrfKeyHash 生成随机性的公钥的ID。该值负责为我们的随机请求生成一个唯一ID，称为requestId
    */
    constructor(
        address vrfCoordinator, 
        address linkToken,
        bytes32 vrfKeyHash,
        uint256 vrfFee
        )VRFConsumerBase(vrfCoordinator, linkToken){
            keyHash = vrfKeyHash;
            fee = vrfFee;
            gameStarted = false;
        }
    
    /**
     *  startGame 通过为所有变量设置合适的值来开始游戏
     *  这个函数onlyOwner意味着它智能由所有者调用
     *  该函数用于启动游戏。调用该函数后玩家可以进入游戏，直到达到限制
     *  它还发出GameStarted事件 
     */
    function startGame(uint8 _maxPlayers, uint256 _entryFee) public onlyOwner {
        // 检查是否有游戏已经在运行
        require(!gameStarted, "Game is currently running");
        // 清空玩家数组
        delete players;
        // 设置这个游戏的最大玩家数量
        maxPlayers = _maxPlayers;
        //设置游戏开始为真
        gameStarted = true;
        //设置游戏的入场费
        entryFee = _entryFee;
        gameId += 1;
        emit GameStarted(gameId, maxPlayers, entryFee);
    }

    /**
     * 当玩家想要进入游戏时调用joinGame
     * 如果maxPlayers 达到限制，它将调用getRandomWinner函数
     */
    function joinGame() public payable {
        //检查游戏是否已经在运行
        require(gameStarted, "Game has not been started yet");
        //检查用户发送的值是否与entryFee匹配
        require(msg.value == entryFee, "Value sent is not equal to entryFee");
        //检查游戏中是否还有空间可以添加另一个玩家
        require(players.length < maxPlayers, "Game is full");
        //将发送者添加到玩家列表中
        players.push(msg.sender);
        emit PlayerJoined(gameId, msg.sender);
        //如果列表已满，则开始赢家的选择过程
        if(players.length == maxPlayers){
            getRandomWinner();
        }
    }

    /**
     * 当VRFCoordinator 接收到有效的VRF证明时，就会调用fulfillRandomness
     * 该函数被覆盖，作用于Chainlink VRF 生成的随机数
     * @param requestId 对于我们发送给VRF Coordinator(协调器),此ID是唯一的
     * @param randomness 这是一个由VRF Coordinator生成并返回给我们的随机uint256
     *
     * 此功能继承字VRFConsumerBase.VRFCoordinator它在收到来自外部世界的随机性后被合约调用。
     * 0到palyers.length-1在收到可以是uint256范围内的任意数字的随机性后，我们使用mod操作符减小它的范围
     * 这为我们选择了一个索引，我们使用该索引从玩家数组中检索获胜者 
     * 它将合约中的所有以太币发送给获胜者，并发出GameEnded event
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal virtual override {
        //我们希望获胜者索引的长度从0到player.length-1
        //为此，我们使用players.length值对其进行修改
        uint256 winnerIndex = randomness % players.length;
        //从玩家数组中获取获胜者地址
        address winner = players[winnerIndex];
        //将合约中的以太币发送给获胜者
        (bool sent,) = winner.call{value:address(this).balance}("");
        require(sent, "Failed to send Ether");
        //发出游戏已经结束的信号
        emit GameEnded(gameId, winner, requestId); 
        //将游戏变量设置为false
        gameStarted = false;
    }

    /**
     * 调用getRandomWinner开始选择随机获胜者的过程
     * 这个函数在我们请求随机性之前首先检查我们的合约是否由LINK代币，因为chainlink合约以Link代币的形式请求费用
     * 然后这个函数调用reuestRandomness 我们继承的函数VRFConsumerBase并开始生成随机数的过程
     */
    function getRandomWinner() private returns(bytes32 requestId) {
        //LINK是VRFConsumerbase中LINK的内部接口
        //在这里，我们使用该界面的BalanceOf方法来确保我们的合约有足够的链接，
        //以便我们可以向VRFCoordinator请求随机性
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK");
        //向VRF Coordinator 提出请求
        //requestRandomness是VRFConsumerBase中的一个函数
        //它开启了随机生成的过程
        return requestRandomness(keyHash, fee);
    }
    
    //数据为空时，接收以太信息
    receive() external payable{}
    //数据不为空时，调用msg后备函数
    fallback() external payable{}

}