import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio()..options.baseUrl = 'https://httpbun.local/';
  });

  test('Uint8List should not be transformed', () async {
    final bytes = Uint8List.fromList(List.generate(10, (index) => index));
    final transformer = dio.transformer = _TestTransformer();
    final r = await dio.put(
      '/put',
      data: bytes,
    );
    expect(transformer.requestTransformed, isFalse);
    expect(r.statusCode, 200);
  });

  test('List<int> should be transformed', () async {
    final ints = List.generate(10, (index) => index);
    final transformer = dio.transformer = _TestTransformer();
    final r = await dio.put(
      '/put',
      data: ints,
    );
    expect(transformer.requestTransformed, isTrue);
    expect(r.data['data'], ints.toString());
  });

  test('stream', () async {
    const str = 'hello 😌';
    final bytes = utf8.encode(str).toList();
    final stream = Stream.fromIterable(bytes.map((e) => [e]));
    final r = await dio.put(
      '/put',
      data: stream,
      options: Options(
        contentType: Headers.textPlainContentType,
        headers: {
          Headers.contentLengthHeader: bytes.length, // set content-length
        },
      ),
    );
    expect(r.data['data'], str);
  });

  test(
    'file stream',
    () async {
      final f = File('test/mock/flutter.png');
      final contentLength = f.lengthSync();
      final r = await dio.put(
        '/put',
        data: f.openRead(),
        options: Options(
          contentType: 'image/png',
          headers: {
            Headers.contentLengthHeader: contentLength, // set content-length
          },
        ),
      );
      expect(r.data['headers']['Content-Length'], contentLength.toString());

      final img = base64Encode(f.readAsBytesSync());
      expect(r.data['data'], img);
    },
    testOn: 'vm',
  );

  test(
    'file stream<Uint8List>',
    () async {
      final f = File('test/mock/flutter.png');
      final contentLength = f.lengthSync();
      final r = await dio.put(
        '/put',
        data: f.readAsBytes().asStream(),
        options: Options(
          contentType: 'image/png',
          headers: {
            Headers.contentLengthHeader: contentLength, // set content-length
          },
        ),
      );
      expect(r.data['headers']['Content-Length'], contentLength.toString());

      final img = base64Encode(f.readAsBytesSync());
      expect(r.data['data'], img);
    },
    testOn: 'vm',
  );

  test('send progress', () async {
    final data = ['aaaa', 'hello 😌', 'dio is a dart http client'];
    final stream = Stream.fromIterable(data.map((e) => e.codeUnits));
    final expanded = data.expand((element) => element.codeUnits);
    bool fullFilled = false;
    final _ = await dio.put(
      '/put',
      data: stream,
      onSendProgress: (a, b) {
        expect(b, expanded.length);
        expect(a <= b, isTrue);
        if (a == b) {
          fullFilled = true;
        }
      },
      options: Options(
        contentType: Headers.textPlainContentType,
        headers: {
          Headers.contentLengthHeader: expanded.length, // set content-length
        },
      ),
    );
    expect(fullFilled, isTrue);
  });
}

class _TestTransformer extends BackgroundTransformer {
  bool requestTransformed = false;

  @override
  Future<String> transformRequest(RequestOptions options) async {
    requestTransformed = true;
    return super.transformRequest(options);
  }
}
