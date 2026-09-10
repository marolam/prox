/// Limits network concurrency while preserving the input order.
Future<List<R>> boundedAsyncMap<T, R>(Iterable<T> items,
    Future<R> Function(T item) map, {int concurrency = 4}) async {
  if (concurrency < 1) throw ArgumentError.value(concurrency, "concurrency");
  final input = items.toList(growable: false);
  final output = List<R?>.filled(input.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < input.length) {
      final index = next++;
      output[index] = await map(input[index]);
    }
  }
  await Future.wait(List.generate(
    input.length < concurrency ? input.length : concurrency, (_) => worker(),
  ));
  return output.cast<R>();
}
