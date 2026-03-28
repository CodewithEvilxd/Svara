import 'dart:io';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/legacy.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/datamodel.dart';
import '../services/audiohandler.dart';
import 'likedsong.dart';

const appDisplayName = 'Svara';
const appPackageName = 'com.codewithevilxd.svara';
const appDeepLinkScheme = 'svara';
const brandFontFamily = 'SvaraSans';
const developerGithubProfile = 'https://github.com/codewithevilxd';
const developerEmailAddress = 'codewithevilxd@gmail.com';
const developerEmailUrl = 'mailto:codewithevilxd@gmail.com';
const developerPortfolioUrl = 'https://nishantdev.space';
const projectRepoUrl = 'https://github.com/codewithevilxd/svara';
const latestReleaseUrl = 'https://github.com/codewithevilxd/svara/releases/latest';
const apiBaseUrl = 'https://rf-snowy.vercel.app/';
const defaultUsername = 'Nishant';

// tab index
final tabIndexProvider = StateProvider<int>((ref) => 0);
final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();

final currentSongProvider = StateProvider<SongDetail?>((ref) => null);

// shufflemanage
final shuffleProvider = StateProvider<bool>((ref) => false);

final repeatModeProvider = StateProvider<RepeatMode>((ref) => RepeatMode.none);

// liked songs
final likedSongsProvider =
    StateNotifierProvider<LikedSongsNotifier, List<String>>(
      (ref) => LikedSongsNotifier(),
    );

// common data
List<Playlist> playlists = [];
List<ArtistDetails> artists = [];
List<Album> albums = [];

PackageInfo packageInfo = PackageInfo(
  appName: appDisplayName,
  packageName: appPackageName,
  version: '1.0.0',
  buildNumber: '1',
);

// internet value
ValueNotifier<bool> hasInternet = ValueNotifier<bool>(true);

// shared datas
List<Playlist> lovePlaylists = [];
List<Playlist> partyPlaylists = [];
List<Playlist> latestTamilPlayList = [];
List<Album> latestTamilAlbums = [];

// profile update
File? profileFile;
String username = defaultUsername;
