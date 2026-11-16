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

/// A phone screen's own search box ([scope], e.g. `'home'` or
/// `'folder:<id>'`): what's typed there doesn't carry over to other
/// screens, and it's cleared when the screen closes.
final screenSearchQueryProvider = NotifierProvider.autoDispose
    .family<SearchQuery, String, String>((scope) => SearchQuery());
