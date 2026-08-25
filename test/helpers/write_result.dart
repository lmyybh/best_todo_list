import 'package:best_todo_list/app/node_write_result.dart';
import 'package:flutter_test/flutter_test.dart';

Future<T> expectWriteSuccess<T>(Future<NodeWriteResult<T>> future) async {
  final result = await future;
  expect(result, isA<NodeWriteSuccess<T>>());
  return (result as NodeWriteSuccess<T>).value;
}
