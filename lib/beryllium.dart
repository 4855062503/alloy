import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:decimal/decimal.dart';

import 'package:zapdart/utils.dart';
import 'package:zapdart/hmac.dart';
import 'package:zapdart/account_forms.dart';

import 'config.dart';
import 'prefs.dart';
import 'utils.dart';

Future<String?> _server() async {
  var testnet = await Prefs.testnetGet();
  var baseUrl = testnet ? ZcServerTestnet : ZcServerMainnet;
  if (baseUrl != null) baseUrl = baseUrl + 'apiv1/';
  return baseUrl;
}

enum ErrorType { None, Network, Auth }

enum BePermission { receive, balance, history, transfer, issue }
enum BeRole { admin, proposer, authorizer }

class BeError {
  final ErrorType type;
  final String msg;

  BeError(this.type, this.msg);

  static BeError none() {
    return BeError(ErrorType.None, 'no error');
  }

  static BeError network() {
    return BeError(ErrorType.Network, 'network error');
  }

  static BeError auth(String msg) {
    try {
      var json = jsonDecode(msg);
      return BeError(ErrorType.Auth, json['message']);
    } catch (_) {
      return BeError(ErrorType.Auth, msg);
    }
  }
}

class UserInfo {
  final String? firstName;
  final String? lastName;
  final String? mobileNumber;
  final String? address;
  final String email;
  final String? photo;
  final String? photoType;
  final Iterable<BePermission>? permissions;
  final Iterable<BeRole> roles;
  final bool kycValidated;
  final String? kycUrl;

  UserInfo(
      this.firstName,
      this.lastName,
      this.mobileNumber,
      this.address,
      this.email,
      this.photo,
      this.photoType,
      this.permissions,
      this.roles,
      this.kycValidated,
      this.kycUrl);

  UserInfo replace(UserInfo info) {
    // selectively replace permissions because websocket events do not include the permissions field
    var permissions = this.permissions;
    if (info.permissions != null) permissions = info.permissions;
    return UserInfo(
        info.firstName,
        info.lastName,
        info.mobileNumber,
        info.address,
        info.email,
        info.photo,
        info.photoType,
        permissions,
        info.roles,
        info.kycValidated,
        info.kycUrl);
  }

  static UserInfo parse(String data) {
    var jsnObj = json.decode(data);
    // check for permissions field because websocket events do not include this field
    List<BePermission>? perms;
    if (jsnObj.containsKey('permissions')) {
      perms = [];
      for (var permName in jsnObj['permissions'])
        for (var perm in BePermission.values)
          if (describeEnum(perm) == permName) perms.add(perm);
    }
    var roles = <BeRole>[];
    for (var roleName in jsnObj['roles'])
      for (var role in BeRole.values)
        if (describeEnum(role) == roleName) roles.add(role);
    return UserInfo(
        jsnObj['first_name'],
        jsnObj['last_name'],
        jsnObj['mobile_number'],
        jsnObj['address'],
        jsnObj['email'],
        jsnObj['photo'],
        jsnObj['photo_type'],
        perms,
        roles,
        jsnObj['kyc_validated'],
        jsnObj['kyc_url']);
  }
}

class UserInfoResult {
  final UserInfo? info;
  final BeError error;

  UserInfoResult(this.info, this.error);
}

class BeApiKey {
  final String token;
  final String secret;

  BeApiKey(this.token, this.secret);
}

class BeApiKeyResult {
  final BeApiKey? apikey;
  final BeError error;

  BeApiKeyResult(this.apikey, this.error);
}

class BeApiKeyRequestResult {
  final String? token;
  final BeError error;

  BeApiKeyRequestResult(this.token, this.error);
}

class BeKycRequestCreateResult {
  final String? kycUrl;
  final BeError error;

  BeKycRequestCreateResult(this.kycUrl, this.error);
}

class BeAsset {
  final String symbol;
  final String name;
  final String coinType;
  final String status;
  final int minConfs;
  final String message;
  final int decimals;

  BeAsset(this.symbol, this.name, this.coinType, this.status, this.minConfs,
      this.message, this.decimals);

  static List<BeAsset> parseAssets(dynamic assets) {
    List<BeAsset> assetList = [];
    for (var item in assets)
      assetList.add(BeAsset(
          item['symbol'],
          item['name'],
          item['coin_type'],
          item['status'],
          item['min_confs'],
          item['message'],
          item['decimals']));
    return assetList;
  }
}

class BeAssetResult {
  final List<BeAsset> assets;
  final BeError error;

  BeAssetResult(this.assets, this.error);

  static BeAssetResult parse(String data) {
    var assets = BeAsset.parseAssets(jsonDecode(data)['assets']);
    return BeAssetResult(assets, BeError.none());
  }
}

class BeMarket {
  final String symbol;
  final String baseSymbol;
  final String quoteSymbol;
  final int precision;
  final String status;
  final String minTrade;
  final String message;

  BeMarket(this.symbol, this.baseSymbol, this.quoteSymbol, this.precision,
      this.status, this.minTrade, this.message);

  static List<BeMarket> parseMarkets(dynamic markets) {
    List<BeMarket> marketList = [];
    for (var item in markets)
      marketList.add(BeMarket(
          item['symbol'],
          item['base_symbol'],
          item['quote_symbol'],
          item['precision'],
          item['status'],
          item['min_trade'],
          item['message']));
    return marketList;
  }
}

class BeMarketResult {
  final List<BeMarket> markets;
  final BeError error;

  BeMarketResult(this.markets, this.error);

  static BeMarketResult parse(String data) {
    var markets = BeMarket.parseMarkets(jsonDecode(data)['markets']);
    return BeMarketResult(markets, BeError.none());
  }
}

class BeRate {
  final Decimal quantity;
  final Decimal rate;

  BeRate(this.quantity, this.rate);
}

class BeOrderbook {
  final List<BeRate> bids;
  final List<BeRate> asks;
  final Decimal minOrder;
  final Decimal baseAssetWithdrawFee;
  final Decimal quoteAssetWithdrawFee;
  final Decimal brokerFee;

  BeOrderbook(this.bids, this.asks, this.minOrder, this.baseAssetWithdrawFee,
      this.quoteAssetWithdrawFee, this.brokerFee);

  static BeOrderbook parse(String data) {
    List<BeRate> bids = [];
    List<BeRate> asks = [];
    var json = jsonDecode(data);
    var orderbook = json['order_book'];
    var minOrder = Decimal.parse(json['min_order']);
    var baseAssetWithdrawFee = Decimal.parse(json['base_asset_withdraw_fee']);
    var quoteAssetWithdrawFee = Decimal.parse(json['quote_asset_withdraw_fee']);
    var brokerFee = Decimal.parse(json['broker_fee']);
    for (var item in orderbook['bids'])
      bids.add(
          BeRate(Decimal.parse(item['quantity']), Decimal.parse(item['rate'])));
    for (var item in orderbook['asks'])
      asks.add(
          BeRate(Decimal.parse(item['quantity']), Decimal.parse(item['rate'])));
    return BeOrderbook(bids, asks, minOrder, baseAssetWithdrawFee,
        quoteAssetWithdrawFee, brokerFee);
  }

  static BeOrderbook empty() {
    return BeOrderbook(
        [], [], Decimal.zero, Decimal.zero, Decimal.zero, Decimal.zero);
  }
}

class BeOrderbookResult {
  final BeOrderbook orderbook;
  final BeError error;

  BeOrderbookResult(this.orderbook, this.error);
}

enum BeMarketSide { bid, ask }

enum BeOrderStatus {
  none,
  created,
  ready,
  incoming,
  confirmed,
  exchange,
  withdraw,
  completed,
  expired,
  cancelled
}

extension EnumEx on String {
  BeOrderStatus toEnum() =>
      BeOrderStatus.values.firstWhere((d) => describeEnum(d) == toLowerCase());
}

class BeBrokerOrder {
  final String token;
  final DateTime date;
  final DateTime expiry;
  final String market;
  final String baseAsset;
  final String quoteAsset;
  final Decimal baseAmount;
  final Decimal quoteAmount;
  final String recipient;
  final BeOrderStatus status;
  final String? paymentUrl;

  BeBrokerOrder(
      this.token,
      this.date,
      this.expiry,
      this.market,
      this.baseAsset,
      this.quoteAsset,
      this.baseAmount,
      this.quoteAmount,
      this.recipient,
      this.status,
      this.paymentUrl);

  static BeBrokerOrder parse(dynamic data) {
    var date = DateTime.parse(data['date']);
    var expiry = DateTime.parse(data['expiry']);
    var baseAmount = Decimal.parse(data['base_amount_dec']);
    var quoteAmount = Decimal.parse(data['quote_amount_dec']);
    var status = (data['status'] as String).toEnum();
    return BeBrokerOrder(
        data['token'],
        date,
        expiry,
        data['market'],
        data['base_asset'],
        data['quote_asset'],
        baseAmount,
        quoteAmount,
        data['recipient'],
        status,
        data['payment_url']);
  }

  static BeBrokerOrder empty() {
    return BeBrokerOrder('', DateTime.now(), DateTime.now(), '', '', '',
        Decimal.zero, Decimal.zero, '', BeOrderStatus.none, null);
  }
}

class BeBrokerOrderResult {
  final BeBrokerOrder order;
  final BeError error;

  BeBrokerOrderResult(this.order, this.error);

  static BeBrokerOrderResult parse(String data) {
    var json = jsonDecode(data);
    BeBrokerOrder order = BeBrokerOrder.parse(json['broker_order']);
    return BeBrokerOrderResult(order, BeError.none());
  }
}

class BeBrokerOrdersResult {
  final List<BeBrokerOrder> orders;
  final BeError error;

  BeBrokerOrdersResult(this.orders, this.error);

  static BeBrokerOrdersResult parse(String data) {
    List<BeBrokerOrder> orderList = [];
    var orders = jsonDecode(data)['broker_orders'];
    for (var item in orders) orderList.add(BeBrokerOrder.parse(item));
    return BeBrokerOrdersResult(orderList, BeError.none());
  }
}

Future<http.Response?> postAndCatch(String url, String body,
    {Map<String, String>? extraHeaders}) async {
  try {
    return await httpPost(Uri.parse(url), body, extraHeaders: extraHeaders);
  } on SocketException catch (e) {
    print(e);
    return null;
  } on TimeoutException catch (e) {
    print(e);
    return null;
  } on http.ClientException catch (e) {
    print(e);
    return null;
  } on ArgumentError catch (e) {
    print(e);
    return null;
  } on HandshakeException catch (e) {
    print(e);
    return null;
  }
}

Future<String?> beServer() async {
  return await _server();
}

Future<BeError> beUserRegister(AccountRegistration reg) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeError.network();
  var url = baseUrl + "user_register";
  var body = jsonEncode({
    "first_name": reg.firstName,
    "last_name": reg.lastName,
    "email": reg.email,
    "mobile_number": reg.mobileNumber,
    "address": reg.address,
    "password": reg.newPassword,
    "photo": reg.photo,
    "photo_type": reg.photoType
  });
  var response = await postAndCatch(url, body);
  if (response == null) return BeError.network();
  if (response.statusCode == 200) {
    return BeError.none();
  } else if (response.statusCode == 400) return BeError.auth(response.body);
  print(response.statusCode);
  return BeError.network();
}

Future<BeApiKeyResult> beApiKeyCreate(
    String email, String password, String deviceName) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeApiKeyResult(null, BeError.network());
  var url = baseUrl + "api_key_create";
  var body = jsonEncode(
      {"email": email, "password": password, "device_name": deviceName});
  var response = await postAndCatch(url, body);
  if (response == null) return BeApiKeyResult(null, BeError.network());
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    var info = BeApiKey(jsnObj["token"], jsnObj["secret"]);
    return BeApiKeyResult(info, BeError.none());
  } else if (response.statusCode == 400)
    return BeApiKeyResult(null, BeError.auth(response.body));
  print(response.statusCode);
  return BeApiKeyResult(null, BeError.network());
}

Future<BeApiKeyRequestResult> beApiKeyRequest(
    String email, String deviceName) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeApiKeyRequestResult(null, BeError.network());
  var url = baseUrl + "api_key_request";
  var body = jsonEncode({"email": email, "device_name": deviceName});
  var response = await postAndCatch(url, body);
  if (response == null) return BeApiKeyRequestResult(null, BeError.network());
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    var token = jsnObj["token"];
    return BeApiKeyRequestResult(token, BeError.none());
  } else if (response.statusCode == 400)
    return BeApiKeyRequestResult(null, BeError.auth(response.body));
  print(response.statusCode);
  return BeApiKeyRequestResult(null, BeError.network());
}

Future<BeApiKeyResult> beApiKeyClaim(String token) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeApiKeyResult(null, BeError.network());
  var url = baseUrl + "api_key_claim";
  var body = jsonEncode({"token": token});
  var response = await postAndCatch(url, body);
  if (response == null) return BeApiKeyResult(null, BeError.network());
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    var info = BeApiKey(jsnObj["token"], jsnObj["secret"]);
    return BeApiKeyResult(info, BeError.none());
  } else if (response.statusCode == 400)
    return BeApiKeyResult(null, BeError.auth(response.body));
  print(response.statusCode);
  return BeApiKeyResult(null, BeError.network());
}

Future<UserInfoResult> beUserInfo({String? email}) async {
  var baseUrl = await _server();
  if (baseUrl == null) return UserInfoResult(null, BeError.network());
  var url = baseUrl + "user_info";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "email": email});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return UserInfoResult(null, BeError.network());
  if (response.statusCode == 200) {
    var info = UserInfo.parse(response.body);
    return UserInfoResult(info, BeError.none());
  } else if (response.statusCode == 400)
    return UserInfoResult(null, BeError.auth(response.body));
  print(response.statusCode);
  return UserInfoResult(null, BeError.network());
}

Future<BeError> beUserResetPassword() async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeError.network();
  var url = baseUrl + "user_reset_password";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeError.network();
  if (response.statusCode == 200) {
    return BeError.none();
  } else if (response.statusCode == 400) return BeError.auth(response.body);
  print(response.statusCode);
  return BeError.network();
}

Future<BeError> beUserUpdateEmail(String email) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeError.network();
  var url = baseUrl + "user_update_email";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "email": email});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeError.network();
  if (response.statusCode == 200) {
    return BeError.none();
  } else if (response.statusCode == 400) return BeError.auth(response.body);
  print(response.statusCode);
  return BeError.network();
}

Future<BeError> beUserUpdatePassword(
    String currentPassword, String newPassword) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeError.network();
  var url = baseUrl + "user_update_password";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({
    "api_key": apikey,
    "nonce": nonce,
    "current_password": currentPassword,
    "new_password": newPassword
  });
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeError.network();
  if (response.statusCode == 200) {
    return BeError.none();
  } else if (response.statusCode == 400) return BeError.auth(response.body);
  print(response.statusCode);
  return BeError.network();
}

Future<BeError> beUserUpdatePhoto(String? photo, String? photoType) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeError.network();
  var url = baseUrl + "user_update_photo";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({
    "api_key": apikey,
    "nonce": nonce,
    "photo": photo,
    "photo_type": photoType
  });
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeError.network();
  if (response.statusCode == 200) {
    return BeError.none();
  } else if (response.statusCode == 400) return BeError.auth(response.body);
  print(response.statusCode);
  return BeError.network();
}

Future<BeKycRequestCreateResult> beKycRequestCreate() async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeKycRequestCreateResult(null, BeError.network());
  var url = baseUrl + "user_kyc_request_create";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null)
    return BeKycRequestCreateResult(null, BeError.network());
  if (response.statusCode == 200) {
    var jsnObj = json.decode(response.body);
    return BeKycRequestCreateResult(jsnObj['kyc_url'], BeError.none());
  } else if (response.statusCode == 400)
    return BeKycRequestCreateResult(null, BeError.auth(response.body));
  print(response.statusCode);
  return BeKycRequestCreateResult(null, BeError.network());
}

Future<BeAssetResult> beAssets() async {
  List<BeAsset> assets = [];
  var baseUrl = await _server();
  if (baseUrl == null) return BeAssetResult(assets, BeError.network());
  var url = baseUrl + "assets";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({
    "api_key": apikey,
    "nonce": nonce,
  });
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeAssetResult(assets, BeError.network());
  if (response.statusCode == 200) {
    return BeAssetResult.parse(response.body);
  } else if (response.statusCode == 400)
    return BeAssetResult(assets, BeError.auth(response.body));
  print(response.statusCode);
  return BeAssetResult(assets, BeError.network());
}

Future<BeMarketResult> beMarkets() async {
  List<BeMarket> markets = [];
  var baseUrl = await _server();
  if (baseUrl == null) return BeMarketResult(markets, BeError.network());
  var url = baseUrl + "markets";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({
    "api_key": apikey,
    "nonce": nonce,
  });
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeMarketResult(markets, BeError.network());
  if (response.statusCode == 200) {
    return BeMarketResult.parse(response.body);
  } else if (response.statusCode == 400)
    return BeMarketResult(markets, BeError.auth(response.body));
  print(response.statusCode);
  return BeMarketResult(markets, BeError.network());
}

Future<BeOrderbookResult> beOrderbook(String symbol) async {
  var baseUrl = await _server();
  if (baseUrl == null)
    return BeOrderbookResult(BeOrderbook.empty(), BeError.network());
  var url = baseUrl + "order_book";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "symbol": symbol});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null)
    return BeOrderbookResult(BeOrderbook.empty(), BeError.network());
  if (response.statusCode == 200) {
    return BeOrderbookResult(BeOrderbook.parse(response.body), BeError.none());
  } else if (response.statusCode == 400)
    return BeOrderbookResult(BeOrderbook.empty(), BeError.auth(response.body));
  print(response.statusCode);
  return BeOrderbookResult(BeOrderbook.empty(), BeError.network());
}

Future<BeBrokerOrderResult> beOrderCreate(
    String market, BeMarketSide side, Decimal amount, String recipient) async {
  var baseUrl = await _server();
  if (baseUrl == null)
    return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
  var url = baseUrl + "broker_order_create";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({
    "api_key": apikey,
    "nonce": nonce,
    "market": market,
    "side": describeEnum(side),
    "amount_dec": amount.toString(),
    "recipient": recipient
  });
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null)
    return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
  if (response.statusCode == 200) {
    return BeBrokerOrderResult.parse(response.body);
  } else if (response.statusCode == 400)
    return BeBrokerOrderResult(
        BeBrokerOrder.empty(), BeError.auth(response.body));
  print(response.statusCode);
  return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
}

Future<BeBrokerOrderResult> beOrderAccept(String token) async {
  var baseUrl = await _server();
  if (baseUrl == null)
    return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
  var url = baseUrl + "broker_order_accept";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "token": token});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null)
    return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
  if (response.statusCode == 200) {
    return BeBrokerOrderResult.parse(response.body);
  } else if (response.statusCode == 400)
    return BeBrokerOrderResult(
        BeBrokerOrder.empty(), BeError.auth(response.body));
  print(response.statusCode);
  return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
}

Future<BeBrokerOrderResult> beOrderStatus(String token) async {
  var baseUrl = await _server();
  if (baseUrl == null)
    return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
  var url = baseUrl + "broker_order_status";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode({"api_key": apikey, "nonce": nonce, "token": token});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null)
    return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
  if (response.statusCode == 200) {
    return BeBrokerOrderResult.parse(response.body);
  } else if (response.statusCode == 400)
    return BeBrokerOrderResult(
        BeBrokerOrder.empty(), BeError.auth(response.body));
  print(response.statusCode);
  return BeBrokerOrderResult(BeBrokerOrder.empty(), BeError.network());
}

Future<BeBrokerOrdersResult> beOrderList(int offset, int limit) async {
  var baseUrl = await _server();
  if (baseUrl == null) return BeBrokerOrdersResult([], BeError.network());
  var url = baseUrl + "broker_orders";
  var apikey = await Prefs.beApiKeyGet();
  var apisecret = await Prefs.beApiSecretGet();
  checkApiKey(apikey, apisecret);
  var nonce = nextNonce();
  var body = jsonEncode(
      {"api_key": apikey, "nonce": nonce, "offset": offset, "limit": limit});
  var sig = createHmacSig(apisecret!, body);
  var response =
      await postAndCatch(url, body, extraHeaders: {"X-Signature": sig});
  if (response == null) return BeBrokerOrdersResult([], BeError.network());
  if (response.statusCode == 200) {
    return BeBrokerOrdersResult.parse(response.body);
  } else if (response.statusCode == 400)
    return BeBrokerOrdersResult([], BeError.auth(response.body));
  print(response.statusCode);
  return BeBrokerOrdersResult([], BeError.network());
}