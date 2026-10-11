import 'package:flutter/material.dart';

import '../../../data/services/image_picker_service.dart';
import '../../features/auth/views/sign_out.dart';
import '../app_services.dart';
import '../theme/app_theme.dart';
import '../widgets/app_error_banner.dart';
import '../widgets/app_primary_button.dart';
import 'photo_editor_view_model.dart';
import 'photo_failure.dart';
import 'photo_image.dart';

/// What the person chose in the source sheet.
enum _Choice { camera, gallery, remove }

/// How the preview sheet ended.
enum _PreviewResult { saved, another, sessionExpired }

/// A photo that can be changed: tap it, choose camera or library (or remove),
/// see a preview, and only then save. One component for every photo (a
/// profile, a store); what differs is the frame ([shape]), the texts, and the
/// two requests handed in.
///
/// While the photo is being saved or removed it cannot be tapped again, and
/// the photo shown stays the persisted one until the backend has the new one.
class EditablePhoto extends StatefulWidget {
  const EditablePhoto({
    required this.shape,
    required this.photoUrl,
    required this.title,
    required this.removeMessage,
    required this.onUpload,
    required this.onRemove,
    this.size = 96,
    super.key,
  });

  final PhotoShape shape;

  /// The persisted photo, or `null` for none. Follows the caller's state.
  final String? photoUrl;

  /// Heading of the source sheet and the preview, e.g. `Photo de profil`.
  final String title;

  /// The confirmation shown before removing, e.g. `Votre photo sera supprimée.`
  final String removeMessage;

  /// Sends the image and updates the state that shows the photo. Throws on
  /// failure.
  final Future<void> Function(PickedImage image) onUpload;

  /// Removes the photo and updates the state that shows it. Throws on failure.
  final Future<void> Function() onRemove;

  /// The avatar's diameter.
  final double size;

  @override
  State<EditablePhoto> createState() => _EditablePhotoState();
}

class _EditablePhotoState extends State<EditablePhoto> {
  PhotoEditorViewModel? _viewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewModel ??= PhotoEditorViewModel(
      picker: AppServices.of(context).imagePickerService,
      upload: widget.onUpload,
      remove: widget.onRemove,
    );
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit() async {
    final viewModel = _viewModel!;
    var choice = await _askSource();
    while (choice != null && mounted) {
      if (choice == _Choice.remove) {
        await _confirmAndRemove();
        return;
      }
      final picked = await viewModel.pick(
        choice == _Choice.camera ? PhotoSource.camera : PhotoSource.gallery,
      );
      if (!mounted) {
        return;
      }
      if (!picked) {
        final failure = viewModel.failure;
        if (failure != null) {
          _show(failure.message);
        }
        return;
      }
      final result = await _showPreview();
      if (!mounted) {
        return;
      }
      switch (result) {
        case _PreviewResult.saved:
          _show('Photo enregistrée.');
          return;
        case _PreviewResult.sessionExpired:
          await signOut(context);
          return;
        case _PreviewResult.another:
          choice = await _askSource();
        case null:
          viewModel.discard();
          return;
      }
    }
  }

  Future<_Choice?> _askSource() {
    return showModalBottomSheet<_Choice>(
      context: context,
      showDragHandle: true,
      shape: _sheetShape,
      builder: (context) =>
          _SourceSheet(title: widget.title, hasPhoto: widget.photoUrl != null),
    );
  }

  Future<_PreviewResult?> _showPreview() {
    return showModalBottomSheet<_PreviewResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      enableDrag: false,
      shape: _sheetShape,
      builder: (context) => _PreviewSheet(
        viewModel: _viewModel!,
        shape: widget.shape,
        title: widget.title,
      ),
    );
  }

  Future<void> _confirmAndRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: Text(widget.removeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final removed = await _viewModel!.remove();
    if (!mounted) {
      return;
    }
    if (removed) {
      _show('Photo supprimée.');
      return;
    }
    final failure = _viewModel!.failure!;
    if (failure.kind == PhotoFailureKind.sessionExpired) {
      await signOut(context);
      return;
    }
    _show(failure.message);
  }

  @override
  Widget build(BuildContext context) {
    final isAvatar = widget.shape == PhotoShape.avatar;
    return ListenableBuilder(
      listenable: _viewModel!,
      builder: (context, _) {
        final viewModel = _viewModel!;
        return Semantics(
          button: true,
          label: widget.title,
          hint: 'Modifier la photo',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: viewModel.isBusy ? null : _edit,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PhotoImage(
                  shape: widget.shape,
                  url: widget.photoUrl,
                  size: widget.size,
                ),
                if (viewModel.isRemoving)
                  Positioned.fill(child: _LoadingScrim(shape: widget.shape)),
                Positioned(
                  right: isAvatar ? 0 : AppSpacing.sm,
                  bottom: isAvatar ? 0 : AppSpacing.sm,
                  child: const _EditBadge(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.sheet)),
);

class _EditBadge extends StatelessWidget {
  const _EditBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
      ),
      child: const Icon(
        Icons.photo_camera_rounded,
        size: 16,
        color: Colors.white,
      ),
    );
  }
}

/// A veil with a spinner over the photo while a request runs.
class _LoadingScrim extends StatelessWidget {
  const _LoadingScrim({required this.shape});

  final PhotoShape shape;

  @override
  Widget build(BuildContext context) {
    final scrim = ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
    return switch (shape) {
      PhotoShape.avatar => ClipOval(child: scrim),
      PhotoShape.banner => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: scrim,
      ),
    };
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.title, required this.hasPhoto});

  final String title;
  final bool hasPhoto;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pagePadding,
              0,
              AppSpacing.pagePadding,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.of(context).pop(_Choice.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.of(context).pop(_Choice.gallery),
          ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
              ),
              title: const Text(
                'Supprimer la photo',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () => Navigator.of(context).pop(_Choice.remove),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// The picked image, and the two ways on: save it, or choose another. Nothing
/// is sent until `Enregistrer`.
class _PreviewSheet extends StatelessWidget {
  const _PreviewSheet({
    required this.viewModel,
    required this.shape,
    required this.title,
  });

  final PhotoEditorViewModel viewModel;
  final PhotoShape shape;
  final String title;

  Future<void> _save(BuildContext context) async {
    final navigator = Navigator.of(context);
    final saved = await viewModel.save();
    if (saved) {
      navigator.pop(_PreviewResult.saved);
    } else if (viewModel.failure?.kind == PhotoFailureKind.sessionExpired) {
      navigator.pop(_PreviewResult.sessionExpired);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final image = viewModel.pending;
        final failure = viewModel.failure;
        final uploading = viewModel.isUploading;
        return PopScope(
          canPop: !uploading,
          child: SafeArea(
            // Scrolls on a short screen (an error banner plus a 16:9 preview).
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.lg),
                  if (failure != null) ...[
                    AppErrorBanner(message: failure.message),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (image != null)
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PhotoPreviewImage(shape: shape, bytes: image.bytes),
                          if (uploading)
                            Positioned.fill(child: _LoadingScrim(shape: shape)),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xxl),
                  AppPrimaryButton(
                    label: 'Enregistrer',
                    isLoading: uploading,
                    onPressed: () => _save(context),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    onPressed: uploading
                        ? null
                        : () {
                            viewModel.discard();
                            Navigator.of(context).pop(_PreviewResult.another);
                          },
                    child: const Text('Choisir une autre'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
