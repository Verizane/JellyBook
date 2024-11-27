// The purpose of this screen is to allow the user to search for a specific book/comic
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:jellybook/models/entry.dart';
import 'package:jellybook/providers/fixRichText.dart';
import 'package:jellybook/screens/infoScreen.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:string_similarity/string_similarity.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:jellybook/widgets/roundedImageWithShadow.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  SearchScreenState createState() => SearchScreenState();
}

// _SearchScreenState
class SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final isar = Isar.getInstance();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Entry> searchResults = [];
  // List<Map<String, dynamic>> searchResults = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Container(
          width: double.infinity,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: TextField(
              autofocus: true,
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    searchResults = [];
                    _searchController.clear();
                  },
                ),
                // only have suffix icon when the search bar is selected
                hintText:
                    (AppLocalizations.of(context)?.search ?? 'Search') + '...',
                border: InputBorder.none,
              ),
              onChanged: (value) async {
                await getSearchResults(value);
              },
              onSubmitted: (value) async {
                await getSearchResults(value);
              },
            ),
          ),
        ),
      ),

      // body based on if searchResults is 0 or not
      body: searchResults.length == 0
          ? _searchController.text.toString().length == 0
              ? Center(
                  child: Text(
                      AppLocalizations.of(context)?.searchBook ??
                          'Please search for a book',
                      style: const TextStyle(
                        fontSize: 20,
                      )),
                )
              : Center(
                  child: Text(
                      AppLocalizations.of(context)?.noResults ??
                          'No results found',
                      style: const TextStyle(
                        fontSize: 20,
                      )),
                )
          : ListView(
              children: [
                for (var i = 0; i < searchResults.length; i++)
                  Card(
                    child: InkWell(
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: SizedBox(
                              width: MediaQuery.of(context).size.width * 0.2,
                              child: Container(
                                width: MediaQuery.of(context).size.width * 0.2,
                                height: MediaQuery.of(context).size.width * 0.3,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.4),
                                      spreadRadius: 5,
                                      blurRadius: 7,
                                      // offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: RoundedImageWithShadow(
                                  imageUrl: searchResults[i].imagePath,
                                ),
                              ),
                            ),
                          ),
                          // have the name be at the top, not centered
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 8.0, bottom: 4.0),
                                  child: AutoSizeText(
                                    searchResults[i].title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: AutoSizeText.rich(
                                    maxLines: 6,
                                    // richtext to allow for bolding
                                    TextSpan(
                                      text: "\t\t\t" +
                                          fixRichText(
                                              searchResults[i].description),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                        fontStyle: FontStyle.italic,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => InfoScreen(
                                entry: searchResults[i],
                              ),
                            )).whenComplete(() async {
                          // update the search results
                          await getSearchResults(
                              _searchController.text.toString());
                        });
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> getSearchResults(String searchQuery) async {
    // get the search results from the database
    var isar = Isar.getInstance();
    // var books = await isar!.entrys
    //     .filter()
    //     .titleContains(searchQuery, caseSensitive: false)
    //     .typeContains("book", caseSensitive: false)
    //     .or()
    //     .titleContains(searchQuery, caseSensitive: false)
    //     .typeContains("comic", caseSensitive: false)
    //     .findAll();
    // instead of using the exact search query, we will fuzzy search
    var books = await isar!.entrys
        .filter()
        .typeEqualTo(EntryType.book)
        .or()
        .typeEqualTo(EntryType.comic)
        .findAll();

    books = diceCoefficientRankings(searchQuery, books);

    // convert the results to a list of maps
    // List<Map<String, dynamic>> results = [];
    // books.forEach((element) {
    //   results.add({
    //     "name": element.title,
    //     "imagePath": element.imagePath,
    //     "description": element.description,
    //     "tags": element.tags,
    //     "url": element.url,
    //     "year": element.releaseDate,
    //     "rating": element.rating,
    //     "stars": element.rating,
    //     "path": element.path,
    //     "id": element.id,
    //     "isLiked": element.isFavorited,
    //     "isDownloaded": element.downloaded,
    //   });
    // });
    setState(() {
      searchResults = books;
    });
  }

  List<Entry> diceCoefficientRankings(String searchQuery, List<Entry> books) {
    // first we will use the entire search query, then we will compare the individual words in the search query to the individual words in the title
    searchQuery = searchQuery.toLowerCase();
    List<String> titles = [];
    List<Map<double, Entry>> rankings = [];
    books.forEach((element) {
      titles.add(element.title.toLowerCase());
    });

    titles.forEach((element) {
      // rank similarity of the entire search query to the title
      double similarity = searchQuery.similarityTo(element);
      List<String> searchWords = searchQuery.split(" ");
      List<String> titleWords = element.split(" ");

      // now we will compare the individual words in the search query to the individual words in the title
      double wordSimilarity = 0;
      searchWords.forEach((searchWord) {
        titleWords.forEach((titleWord) {
          wordSimilarity += searchWord.similarityTo(titleWord);
        });
      });
      wordSimilarity =
          wordSimilarity / (searchWords.length * titleWords.length);

      double finalSimilarity = (similarity + 2 * wordSimilarity) / 2;

      rankings.add({finalSimilarity: books[titles.indexOf(element)]});
    });
    // now we will sort the rankings
    rankings.sort((a, b) => b.keys.first.compareTo(a.keys.first));
    // now we will convert the rankings to a list of books
    List<Entry> results = [];
    rankings.forEach((element) {
      results.add(element.values.first);
    });
    double div = searchQuery.length / 10;
    // remove anything before the decimal
    div = div - div.floor();

    return results
        .where((element) =>
            rankings[results.indexOf(element)].keys.first >= 0.4 * (1 - div))
        .toList();
  }

  List<Entry> diceCoefficientRankings2(String searchQuery, List<Entry> books) {
    searchQuery = searchQuery.toLowerCase();
    List<String> titles = [];
    List<Map<double, Entry>> rankings = [];
    books.forEach((element) {
      titles.add(element.title.toLowerCase());
    });

    titles.forEach((element) {
      // rank similarity of the entire search query to the title
      double similarity = searchQuery.similarityTo(element);
      List<String> searchWords = searchQuery.split(" ");
      List<String> titleWords = element.split(" ");

      // now we will compare the individual words in the search query to the individual words in the title
      double wordSimilarity = 0;
      searchWords.forEach((searchWord) {
        titleWords.forEach((titleWord) {
          wordSimilarity += searchWord.similarityTo(titleWord);
        });
      });
      wordSimilarity =
          wordSimilarity / (searchWords.length * titleWords.length);

      double finalSimilarity = (similarity + 2 * wordSimilarity) / 2;

      rankings.add({finalSimilarity: books[titles.indexOf(element)]});
    });

    // Use quicksort to sort the rankings
    quicksort(rankings, 0, rankings.length - 1);

    // now we will convert the rankings to a list of books
    List<Entry> results = [];
    rankings.forEach((element) {
      results.add(element.values.first);
    });
    double div = searchQuery.length / 10;
    // remove anything before the decimal
    div = div - div.floor();

// return first 20 results (or less if there are less than 20 results)
    return results.toList().sublist(0, min(20, results.length));

    // return results
    //     .where((element) =>
    //         rankings[results.indexOf(element)].keys.first >= 0.4 * (1 - div))
    //     .toList();
  }

  void quicksort(List<Map<double, Entry>> rankings, int low, int high) {
    if (low < high) {
      int pivotIndex = partition(rankings, low, high);
      quicksort(rankings, low, pivotIndex - 1);
      quicksort(rankings, pivotIndex + 1, high);
    }
  }

  int partition(List<Map<double, Entry>> rankings, int low, int high) {
    double pivot = rankings[high].keys.first;
    int i = low - 1;
    for (int j = low; j < high; j++) {
      if (rankings[j].keys.first < pivot) {
        i++;
        Map<double, Entry> temp = rankings[i];
        rankings[i] = rankings[j];
        rankings[j] = temp;
      }
    }
    Map<double, Entry> temp = rankings[i + 1];
    rankings[i + 1] = rankings[high];
    rankings[high] = temp;
    return i + 1;
  }
}
