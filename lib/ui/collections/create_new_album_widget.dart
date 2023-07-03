import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection.dart";
import "package:photos/models/collection_items.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/navigation_util.dart";

class CreateNewAlbumIcon extends StatelessWidget {
  const CreateNewAlbumIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButtonWidget(
      icon: Icons.add_rounded,
      iconButtonType: IconButtonType.primary,
      onTap: () async {
        final result = await showTextInputDialog(
          context,
          title: S.of(context).newAlbum,
          submitButtonLabel: S.of(context).create,
          hintText: S.of(context).enterAlbumName,
          alwaysShowSuccessState: false,
          initialValue: "",
          textCapitalization: TextCapitalization.words,
          onSubmit: (String text) async {
            // indicates user cancelled the rename request
            if (text.trim() == "") {
              return;
            }

            try {
              final Collection c =
                  await CollectionsService.instance.createAlbum(text);
              routeToPage(
                  context, CollectionPage(CollectionWithThumbnail(c, null)));
            } catch (e, s) {
              Logger("CreateNewAlbumIcon")
                  .severe("Failed to rename album", e, s);
              rethrow;
            }
          },
        );
        if (result is Exception) {
          showGenericErrorDialog(context: context);
        }
      },
    );
  }
}
