import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/models/store.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';

/// The text controllers behind [StoreFormFields]. Owned (and disposed) by the
/// screen that hosts the form, so it can read the values on submit.
class StoreFormControllers {
  StoreFormControllers({Store? store})
    : name = TextEditingController(text: store?.name),
      address = TextEditingController(text: store?.address),
      description = TextEditingController(text: store?.description),
      photo = TextEditingController(text: store?.photo),
      latitude = TextEditingController(text: store?.latitude?.toString()),
      longitude = TextEditingController(text: store?.longitude?.toString());

  final TextEditingController name;
  final TextEditingController address;
  final TextEditingController description;
  final TextEditingController photo;
  final TextEditingController latitude;
  final TextEditingController longitude;

  /// `null` when the field is empty. Only call after the form validated.
  double? get latitudeValue => _parse(latitude);
  double? get longitudeValue => _parse(longitude);

  static double? _parse(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : double.parse(text);
  }

  void dispose() {
    name.dispose();
    address.dispose();
    description.dispose();
    photo.dispose();
    latitude.dispose();
    longitude.dispose();
  }
}

/// The store details form, shared by store creation and store editing so both
/// collect exactly the same fields with the same validation.
class StoreFormFields extends StatelessWidget {
  const StoreFormFields({
    required this.controllers,
    required this.onSubmit,
    super.key,
  });

  final StoreFormControllers controllers;

  /// Called when the keyboard's "done" is pressed on the last field.
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: controllers.name,
          textInputAction: TextInputAction.next,
          inputFormatters: [LengthLimitingTextInputFormatter(AppLimits.name)],
          decoration: const InputDecoration(labelText: 'Nom du magasin'),
          validator: AppValidators.storeName,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: controllers.address,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(AppLimits.address),
          ],
          keyboardType: TextInputType.streetAddress,
          decoration: const InputDecoration(
            labelText: 'Adresse du magasin',
            hintText: 'Où vos clients viendront retirer leur commande',
          ),
          validator: AppValidators.storeAddress,
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: controllers.description,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(AppLimits.description),
          ],
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description',
            hintText: 'Optionnel',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: controllers.photo,
          textInputAction: TextInputAction.next,
          keyboardType: TextInputType.url,
          inputFormatters: [LengthLimitingTextInputFormatter(AppLimits.url)],
          decoration: const InputDecoration(
            labelText: 'Photo du magasin',
            hintText: 'Lien de la photo (optionnel)',
          ),
          validator: AppValidators.optionalPhotoUrl,
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text('Localisation', style: textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Optionnel — coordonnées GPS du magasin.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: controllers.latitude,
                textInputAction: TextInputAction.next,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Latitude'),
                validator: (value) =>
                    AppValidators.optionalLatitude(value) ??
                    AppValidators.coordinatePair(
                      value,
                      controllers.longitude.text,
                      message: 'Renseignez aussi la latitude.',
                    ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: TextFormField(
                controller: controllers.longitude,
                textInputAction: TextInputAction.done,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(labelText: 'Longitude'),
                validator: (value) =>
                    AppValidators.optionalLongitude(value) ??
                    AppValidators.coordinatePair(
                      value,
                      controllers.latitude.text,
                      message: 'Renseignez aussi la longitude.',
                    ),
                onFieldSubmitted: (_) => onSubmit(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
