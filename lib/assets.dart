import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'beryllium.dart';

String _svgAsset(String symbol) {
  switch (symbol) {
    case 'BTC':
      return 'assets/crypto_logos/bitcoin.svg';
    case 'ETH':
      return 'assets/crypto_logos/ethereum.svg';
    case 'DOGE':
      return 'assets/crypto_logos/dogecoin.svg';
    case 'LTC':
      return 'assets/crypto_logos/litecoin.svg';
  }
  return 'assets/crypto_logos/default.svg';
}

Widget assetLogo(String symbol, {EdgeInsetsGeometry? margin}) {
  return Container(
      margin: margin,
      width: 32,
      height: 32,
      child: Center(child: SvgPicture.asset(_svgAsset(symbol))));
}

String? addressBlockExplorer(String symbol, bool testnet, String address) {
  switch (symbol) {
    case 'BTC':
      if (testnet) return 'https://blockstream.info/testnet/address/$address';
      return 'https://blockstream.info/address/$address';
    case 'ETH':
      if (testnet)
        return 'https://ropsten.etherscan.io/testnet/address/$address';
      return 'https://etherscan.io/address/$address';
    case 'DOGE':
      if (testnet) return null;
      return 'https://blockchair.com/dogecoin/address/$address';
    case 'LTC':
      if (testnet) return null;
      return 'https://blockchair.com/litecoin/address/$address';
  }
  return null;
}

class AssetScreen extends StatelessWidget {
  final List<BeAsset> assets;

  AssetScreen(this.assets);

  Widget _listItem(BuildContext context, int n) {
    var asset = assets[n];
    return ListTile(
      title: Text('${asset.symbol}'),
      leading: assetLogo(asset.symbol),
      subtitle: Text(
          'name: ${asset.name}, status: ${asset.status}, minimum confirmations: ${asset.minConfs}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Assets'),
      ),
      body: ListView.builder(itemBuilder: _listItem, itemCount: assets.length),
    );
  }
}
