# RCCStake智能合约

RCCStake是一个基于以太坊的智能合约，用于管理代币质押和提取功能。用户可以将代币存入合约，并在满足一定条件后提取这些代币。

## 功能

- 质押代币
- 提取质押代币
- 计算奖励

## 部署

1. 克隆仓库：

```bash
git clone https://github.com/conanJiang/RCCStake.git
```

2. 安装依赖：

```bash
cd RCCStake
npm install
```

3. 编译合约：

```bash
truffle compile
```

4. 部署合约：

```bash
truffle migrate
```

## 使用

1. 连接到以太坊网络。
2. 调用`stake`函数质押代币。
3. 调用`withdraw`函数提取质押的代币。

## 安全性

RCCStake合约采用了以下措施来防止重入攻击：

- 使用互斥锁（Mutex）。
- 检查-生效-交互模式（Checks-Effects-Interactions）。
- 使用`SafeMath`库防止整数溢出。
- 使用`ReentrancyGuard`库防止重入攻击。

## 贡献

如果你有任何改进意见或想要贡献代码，请随时提交Pull Request或创建Issue。

## 许可证

RCCStake合约采用MIT许可证。请查看LICENSE文件了解更多信息。


