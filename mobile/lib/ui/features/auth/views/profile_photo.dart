import 'package:flutter/material.dart';

import '../../../core/photo/editable_photo.dart';
import '../../../core/photo/photo_image.dart';
import '../view_models/auth_scope.dart';

/// The signed-in user's own photo, editable. Used by the customer's profile and
/// the owner's home, so both behave identically.
class ProfilePhoto extends StatelessWidget {
  const ProfilePhoto({this.size = 96, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => EditablePhoto(
        shape: PhotoShape.avatar,
        size: size,
        photoUrl: auth.currentUser?.photo,
        title: 'Photo de profil',
        removeMessage: 'Votre photo de profil sera supprimée.',
        onUpload: auth.setPhoto,
        onRemove: auth.removePhoto,
      ),
    );
  }
}
