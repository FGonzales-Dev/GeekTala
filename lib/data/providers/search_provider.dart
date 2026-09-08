import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current search box text — shared between the search field itself
/// (desktop sidebar / mobile top bar) and whichever notes list is showing
/// results, since they're separate widgets.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);
