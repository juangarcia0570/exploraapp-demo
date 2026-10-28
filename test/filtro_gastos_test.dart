import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:exploraec/controllers/auth_controller.dart';
import 'package:exploraec/controllers/gastos_controller.dart';
import 'package:exploraec/screens/gastos_screen.dart';
import 'package:exploraec/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';

/// Servidor falso con lo mínimo para abrir la pantalla Gastos con sesión:
/// token, usuario, categorías y una lista fija de gastos de dos categorías.
class _Servidor implements HttpClientAdapter {
  final gastos = [
    {'id': 1, 'descripcion': 'Almuerzo Mercado', 'monto': 12.5, 'categoria': 'comida', 'fecha': '2026-10-08'},
    {'id': 2, 'descripcion': 'Taxi al centro', 'monto': 8.0, 'categoria': 'transporte', 'fecha': '2026-10-08'},
    {'id': 3, 'descripcion': 'Cena centro', 'monto': 20.0, 'categoria': 'comida', 'fecha': '2026-10-08'},
  ];

  ResponseBody _json(Object cuerpo, [Map<String, List<String>> h = const {}]) => ResponseBody.fromString(
      jsonEncode(cuerpo), 200,
      headers: {Headers.contentTypeHeader: ['application/json'], ...h});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? cuerpo, Future<void>? cancelar) async {
    switch (o.path) {
      case '/usuarios/token':
        return _json({'access_token': 'tok-a@b.com', 'token_type': 'bearer'});
      case '/usuarios/me':
        return _json({'id': 1, 'email': 'a@b.com'});
      case '/gastos/categorias':
        return _json({'categorias': ['comida', 'transporte', 'entretenimiento', 'otros'], 'limite_por_categoria': 500.0});
      case '/gastos/':
        return _json(gastos, {'x-total-count': ['${gastos.length}']});
    }
    return ResponseBody.fromString(jsonEncode({'detail': 'ruta no prevista: ${o.path}'}), 404,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _esperar(bool Function() condicion) async {
  for (var i = 0; i < 200 && !condicion(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('hive_filtro').path));

  testWidgets('Filtro por categoría — elegir «comida» muestra solo los gastos de comida', (tester) async {
    Get.reset();
    Get.testMode = true;
    FlutterSecureStorage.setMockInitialValues({});
    Get.put(ApiClient(dio: Dio(BaseOptions(baseUrl: 'http://prueba'))..httpClientAdapter = _Servidor()));
    final auth = Get.put(AuthController());

    // Hive y dio hacen E/S real: se ejecutan fuera del reloj falso de la prueba.
    late GastosController gastos;
    await tester.runAsync(() async {
      await _esperar(() => !auth.restaurando.value);
      await auth.iniciarSesion('a@b.com', 'clave-1234');
      gastos = Get.put(GastosController());
      await _esperar(() => gastos.gastos.length == 3 && gastos.estado.value.name == 'exito');
    });

    await tester.pumpWidget(const GetMaterialApp(home: GastosScreen()));
    await tester.pump();
    expect(find.text('Almuerzo Mercado'), findsOneWidget);
    expect(find.text('Taxi al centro'), findsOneWidget);
    expect(find.text('Cena centro'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'comida'));
    await tester.pump();
    expect(find.text('Almuerzo Mercado'), findsOneWidget);
    expect(find.text('Cena centro'), findsOneWidget);
    expect(find.text('Taxi al centro'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Todas'));
    await tester.pump();
    expect(find.text('Taxi al centro'), findsOneWidget);
    expect(find.text('Almuerzo Mercado'), findsOneWidget);
    expect(find.text('Cena centro'), findsOneWidget);
  });
}
