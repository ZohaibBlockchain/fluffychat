import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_gen/gen_l10n/l10n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/custom_http_client.dart';
import 'package:fluffychat/utils/custom_image_resizer.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_hive_collections_database.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'matrix_sdk_extensions/flutter_matrix_sdk_database_builder.dart';

abstract class ClientManager {
  static const String clientNamespace = 'im.fluffychat.store.clients';
  static Future<List<Client>> getClients({
    bool initialize = true,
    required SharedPreferences store,
  }) async {
    if (PlatformInfos.isLinux) {
      Hive.init((await getApplicationSupportDirectory()).path);
    } else {
      await Hive.initFlutter();
    }
    final clientNames = <String>{};
    try {
      final clientNamesList = store.getStringList(clientNamespace) ?? [];
      clientNames.addAll(clientNamesList);
    } catch (e, s) {
      Logs().w('Client names in store are corrupted', e, s);
      await store.remove(clientNamespace);
    }
    if (clientNames.isEmpty) {
      clientNames.add(PlatformInfos.clientName);
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    final clients = clientNames.map(createClient).toList();
    if (initialize) {
      FlutterLocalNotificationsPlugin? flutterLocalNotificationsPlugin;
      await Future.wait(
        clients.map(
          (client) => client
              .init(
                waitForFirstSync: false,
                waitUntilLoadCompletedLoaded: false,
                onMigration: () {
                  sendMigrationNotification(
                    flutterLocalNotificationsPlugin ??=
                        FlutterLocalNotificationsPlugin(),
                  );
                },
              )
              .catchError(
                (e, s) => Logs().e('Unable to initialize client', e, s),
              ),
        ),
      );
      flutterLocalNotificationsPlugin?.cancel(0);
    }
    if (clients.length > 1 && clients.any((c) => !c.isLogged())) {
      final loggedOutClients = clients.where((c) => !c.isLogged()).toList();
      for (final client in loggedOutClients) {
        Logs().w(
          'Multi account is enabled but client ${client.userID} is not logged in. Removing...',
        );
        clientNames.remove(client.clientName);
        clients.remove(client);
      }
      await store.setStringList(clientNamespace, clientNames.toList());
    }
    return clients;
  }

  static Future<void> addClientNameToStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.add(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static Future<void> removeClientNameFromStore(
    String clientName,
    SharedPreferences store,
  ) async {
    final clientNamesList = store.getStringList(clientNamespace) ?? [];
    clientNamesList.remove(clientName);
    await store.setStringList(clientNamespace, clientNamesList);
  }

  static NativeImplementations get nativeImplementations => kIsWeb
      ? const NativeImplementationsDummy()
      : NativeImplementationsIsolate(compute);

  static Client createClient(String clientName) {
    return Client(
      clientName,
      httpClient:
          PlatformInfos.isAndroid ? CustomHttpClient.createHTTPClient() : null,
      verificationMethods: {
        KeyVerificationMethod.numbers,
        if (kIsWeb || PlatformInfos.isMobile || PlatformInfos.isLinux)
          KeyVerificationMethod.emoji,
      },
      importantStateEvents: <String>{
        // To make room emotes work
        'im.ponies.room_emotes',
        // To check which story room we can post in
        EventTypes.RoomPowerLevels,
      },
      logLevel: kReleaseMode ? Level.warning : Level.verbose,
      databaseBuilder: flutterMatrixSdkDatabaseBuilder,
      legacyDatabaseBuilder: FlutterHiveCollectionsDatabase.databaseBuilder,
      supportedLoginTypes: {
        AuthenticationTypes.password,
        AuthenticationTypes.sso,
      },
      nativeImplementations: nativeImplementations,
      customImageResizer: PlatformInfos.isMobile ? customImageResizer : null,
      enableDehydratedDevices: true,
    );
  }

  static void sendMigrationNotification(
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  ) async {
    final l10n = lookupL10n(Locale(Platform.localeName));

    if (kIsWeb) {
      html.Notification(
        l10n.databaseMigrationTitle,
        body: l10n.databaseMigrationBody,
      );
    }

    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('notifications_icon'),
        iOS: DarwinInitializationSettings(),
      ),
    );

    flutterLocalNotificationsPlugin.show(
      0,
      l10n.databaseMigrationTitle,
      l10n.databaseMigrationBody,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConfig.pushNotificationsChannelId,
          AppConfig.pushNotificationsChannelName,
          channelDescription: AppConfig.pushNotificationsChannelDescription,
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true, // To show notification popup
          showProgress: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
