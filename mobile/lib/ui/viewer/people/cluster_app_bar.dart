import 'dart:async';

import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import "package:ml_linalg/linalg.dart";
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/db/files_db.dart";
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/face/db.dart";
import "package:photos/face/model/person.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/services/collections_service.dart';
import "package:photos/services/machine_learning/face_ml/face_clustering/cosine_distance.dart";
import "package:photos/services/machine_learning/face_ml/face_ml_result.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import "package:photos/ui/common/popup_item.dart";
import "package:photos/ui/viewer/people/cluster_breakup_page.dart";

class ClusterAppBar extends StatefulWidget {
  final GalleryType type;
  final String? title;
  final SelectedFiles selectedFiles;
  final int clusterID;
  final PersonEntity? person;

  const ClusterAppBar(
    this.type,
    this.title,
    this.selectedFiles,
    this.clusterID, {
    this.person,
    Key? key,
  }) : super(key: key);

  @override
  State<ClusterAppBar> createState() => _AppBarWidgetState();
}

enum ClusterPopupAction {
  setCover,
  breakupCluster,
  hide,
}

class _AppBarWidgetState extends State<ClusterAppBar> {
  final _logger = Logger("_AppBarWidgetState");
  late StreamSubscription _userAuthEventSubscription;
  late Function() _selectedFilesListener;
  String? _appBarTitle;
  late CollectionActions collectionActions;
  final GlobalKey shareButtonKey = GlobalKey();
  bool isQuickLink = false;
  late GalleryType galleryType;

  @override
  void initState() {
    super.initState();
    _selectedFilesListener = () {
      setState(() {});
    };
    collectionActions = CollectionActions(CollectionsService.instance);
    widget.selectedFiles.addListener(_selectedFilesListener);
    _userAuthEventSubscription =
        Bus.instance.on<SubscriptionPurchasedEvent>().listen((event) {
      setState(() {});
    });
    _appBarTitle = widget.title;
    galleryType = widget.type;
  }

  @override
  void dispose() {
    _userAuthEventSubscription.cancel();
    widget.selectedFiles.removeListener(_selectedFilesListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      elevation: 0,
      centerTitle: false,
      title: Text(
        _appBarTitle!,
        style:
            Theme.of(context).textTheme.headlineSmall!.copyWith(fontSize: 16),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      actions: kDebugMode ? _getDefaultActions(context) : null,
    );
  }

  List<Widget> _getDefaultActions(BuildContext context) {
    final List<Widget> actions = <Widget>[];
    // If the user has selected files, don't show any actions
    if (widget.selectedFiles.files.isNotEmpty ||
        !Configuration.instance.hasConfiguredAccount()) {
      return actions;
    }

    final List<EntePopupMenuItem<ClusterPopupAction>> items = [];

    items.addAll(
      [
        EntePopupMenuItem(
          "Hide person",
          value: ClusterPopupAction.hide,
          icon: Icons.hide_image_outlined,
        ),
        EntePopupMenuItem(
          "Break up cluster",
          value: ClusterPopupAction.breakupCluster,
          icon: Icons.analytics_outlined,
        ),
      ],
    );

    if (items.isNotEmpty) {
      actions.add(
        PopupMenuButton(
          itemBuilder: (context) {
            return items;
          },
          onSelected: (ClusterPopupAction value) async {
            if (value == ClusterPopupAction.breakupCluster) {
              // ignore: unawaited_futures
              await _breakUpCluster(context);
            } else if (value == ClusterPopupAction.hide) {
              await ClusterFeedbackService.instance
                  .hideCluster(widget.clusterID);
              Navigator.of(context).pop(); // Close the cluster page
            }
            // else if (value == ClusterPopupAction.setCover) {
            //   await setCoverPhoto(context);
          },
        ),
      );
    }

    return actions;
  }

  @Deprecated(
    'Used for debugging an issue with conflicts on cluster IDs, resolved now',
  )
  Future<void> _validateCluster(BuildContext context) async {
    _logger.info('_validateCluster called');
    final faceMlDb = FaceMLDataDB.instance;

    final faceIDs = await faceMlDb.getFaceIDsForCluster(widget.clusterID);
    final fileIDs = faceIDs.map((e) => getFileIdFromFaceId(e)).toList();

    final embeddingsBlobs = await faceMlDb.getFaceEmbeddingMapForFile(fileIDs);
    embeddingsBlobs.removeWhere((key, value) => !faceIDs.contains(key));
    final embeddings = embeddingsBlobs
        .map((key, value) => MapEntry(key, EVector.fromBuffer(value).values));

    for (final MapEntry<String, List<double>> embedding in embeddings.entries) {
      double closestDistance = double.infinity;
      double closestDistance32 = double.infinity;
      double closestDistance64 = double.infinity;
      String? closestFaceID;
      for (final MapEntry<String, List<double>> otherEmbedding
          in embeddings.entries) {
        if (embedding.key == otherEmbedding.key) {
          continue;
        }
        final distance64 = cosineDistanceSIMD(
          Vector.fromList(embedding.value, dtype: DType.float64),
          Vector.fromList(otherEmbedding.value, dtype: DType.float64),
        );
        final distance32 = cosineDistanceSIMD(
          Vector.fromList(embedding.value, dtype: DType.float32),
          Vector.fromList(otherEmbedding.value, dtype: DType.float32),
        );
        final distance = cosineDistForNormVectors(
          embedding.value,
          otherEmbedding.value,
        );
        if (distance < closestDistance) {
          closestDistance = distance;
          closestDistance32 = distance32;
          closestDistance64 = distance64;
          closestFaceID = otherEmbedding.key;
        }
      }
      if (closestDistance > 0.3) {
        _logger.severe(
          "Face ${embedding.key} is similar to $closestFaceID with distance $closestDistance, and float32 distance $closestDistance32, and float64 distance $closestDistance64",
        );
      }
    }
  }

  Future<void> _breakUpCluster(BuildContext context) async {
    final newClusterIDToFaceIDs =
        await ClusterFeedbackService.instance.breakUpCluster(widget.clusterID);

    final allFileIDs = newClusterIDToFaceIDs.values
        .expand((e) => e)
        .map((e) => getFileIdFromFaceId(e))
        .toList();

    final fileIDtoFile = await FilesDB.instance.getFilesFromIDs(
      allFileIDs,
    );

    final newClusterIDToFiles = newClusterIDToFaceIDs.map(
      (key, value) => MapEntry(
        key,
        value
            .map((faceId) => fileIDtoFile[getFileIdFromFaceId(faceId)]!)
            .toList(),
      ),
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ClusterBreakupPage(
          newClusterIDToFiles,
          "(Analysis)",
        ),
      ),
    );
  }
}
