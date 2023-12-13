import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:matrix_homeserver_recommendations/matrix_homeserver_recommendations.dart';

import 'package:fluffychat/config/app_config.dart';
import 'homeserver_bottom_sheet.dart';
import 'homeserver_picker.dart';

class HomeserverAppBar extends StatelessWidget {
  final HomeserverPickerController controller;

  const HomeserverAppBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container();
    // or alternatively, you can use
    // return SizedBox();
  }
}