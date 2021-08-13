// uncomment if you need to override the app theme
//import 'package:flutter/material.dart';
//import 'package:google_fonts/google_fonts.dart';
//import 'package:flutter_icons/flutter_icons.dart';

import 'package:zapdart/colors.dart';

// the default testnet value
const TestnetDefault = true;

// PayDB settings
const String? PayDBServerMainnet = null;
const String? PayDBServerTestnet =
    'https://premio-demo.caprover.acuerdo.dev/paydb/';
// registration
const bool RequireMobileNumber = true;
const String? InitialMobileCountry = 'NZ';
const List<String>? PreferredMobileCountries = [
  'New Zealand',
  'Australia',
  'United States of America'
];
const bool RequireAddress = true;
const String? GooglePlaceApiKeyIOS = null;
const String? GooglePlaceApiKeyAndroid = null;
const String? LocationIqApiKeyIOS = 'pk.e53109b5fdcb2dfd00bbc57c8b713d79';
const String? LocationIqApiKeyAndroid = 'pk.e53109b5fdcb2dfd00bbc57c8b713d79';

void initConfig() {
  overrideTheme();
  // example
  /*overrideTheme(
    zapWhite: Colors.lightBlue[50],
    zapYellow: Colors.teal[100],
    zapWarning: Colors.yellow,
    zapWarningLight: Colors.yellow[100],
    zapBlue: Colors.pink[200],
    zapBlueGradient: LinearGradient(colors: [Colors.pink[200]!, Colors.pink[400]!]),
    zapGreen: Colors.blueGrey[300],
    zapGreenGradient: LinearGradient(colors: [Colors.blueGrey[300]!, Colors.blueGrey[500]!]),
    zapOutgoingFunds: Colors.red,
    zapIncomingFunds: Colors.green,
    zapTextThemer: GoogleFonts.sansitaTextTheme);
    */
}
