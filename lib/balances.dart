import 'package:flutter/material.dart';

import 'beryllium.dart';
import 'websocket.dart';
import 'assets.dart';
import 'widgets.dart';
import 'config.dart';

class BalanceScreen extends StatefulWidget {
  final List<BeBalance> balances;
  final Websocket websocket;

  BalanceScreen(this.balances, this.websocket);

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  Widget _listItem(BuildContext context, int n) {
    var balance = widget.balances[n];
    return ListTile(
        title: Text('${balance.asset}'),
        leading: assetLogo(balance.asset),
        subtitle: Text(
            'total: ${assetFormatWithUnitToUser(balance.asset, balance.total)}, available: ${assetFormatWithUnitToUser(balance.asset, balance.available)}'));
  }

  @override
  Widget build(BuildContext context) {
    double formWidgetsWidth = (MediaQuery.of(context).size.width >= 1440.0)
        ? buttonDesktopWidth
        : MediaQuery.of(context).size.width - 80;
    return Scaffold(
        appBar: AppBar(
          title: Text('Balances'),
        ),
        body: ColumnView(
          child: Center(
              child: SizedBox(
                  width: formWidgetsWidth,
                  child: ListView.builder(
                      itemBuilder: _listItem,
                      itemCount: widget.balances.length))),
        ));
  }
}
