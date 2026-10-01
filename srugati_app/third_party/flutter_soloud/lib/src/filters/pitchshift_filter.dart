// ignore_for_file: public_member_api_docs

import 'package:flutter_soloud/src/filters/filters.dart';
import 'package:flutter_soloud/src/soloud.dart';
import 'package:flutter_soloud/src/sound_handle.dart';
import 'package:flutter_soloud/src/sound_hash.dart';

enum PitchShiftEnum {
  wet,
  shift,
  semitones,
  formantPreserve;

  final List<double> _mins = const [0, 0, -36, 0];
  final List<double> _maxs = const [1, 3, 36, 1];
  final List<double> _defs = const [1, 1, 0, 0];

  double get min => _mins[index];
  double get max => _maxs[index];
  double get def => _defs[index];

  @override
  String toString() => switch (this) {
    PitchShiftEnum.wet => 'Wet',
    PitchShiftEnum.shift => 'Shift',
    PitchShiftEnum.semitones => 'Semitones',
    PitchShiftEnum.formantPreserve => 'FormantPreserve',
  };
}

abstract class _PitchShiftInternal extends FilterBase {
  const _PitchShiftInternal(SoundHash? soundHash, int? busId)
    : super(FilterType.pitchShiftFilter, soundHash, busId);

  PitchShiftEnum get queryWet => PitchShiftEnum.wet;
  PitchShiftEnum get queryShift => PitchShiftEnum.shift;
  PitchShiftEnum get querySemitones => PitchShiftEnum.semitones;
  PitchShiftEnum get queryFormantPreserve => PitchShiftEnum.formantPreserve;
}

class PitchShiftSingle extends _PitchShiftInternal {
  PitchShiftSingle(super.soundHash, super.busId);

  FilterParam wet({SoundHandle? soundHandle}) => FilterParam(
    soundHandle,
    super.busId,
    filterType,
    PitchShiftEnum.wet.index,
    PitchShiftEnum.wet.min,
    PitchShiftEnum.wet.max,
  );

  /// The shift value of the pitch, where 1.0 means the pitch is not shifted.
  ///
  /// Note that both the [shift] and [semitones] parameters are acting to modify
  /// the pitch value, but using different scales. Changing this value will
  /// therefore adjust the [semitones] parameter with:
  /// ```dart
  /// shift = pow(2., value / 12);
  /// ```
  FilterParam shift({SoundHandle? soundHandle}) => FilterParam(
    soundHandle,
    super.busId,
    filterType,
    PitchShiftEnum.shift.index,
    PitchShiftEnum.shift.min,
    PitchShiftEnum.shift.max,
  );

  /// The number of semitones that the pitch is shifted.
  ///
  /// Note that both the [shift] and [semitones] parameters are acting to modify
  /// the pitch value, but using different scales. Changing this value will
  /// therefore adjust the [semitones] parameter with:
  /// ```dart
  /// semitones = 12 * log2f(value);
  /// ```
  FilterParam semitones({SoundHandle? soundHandle}) => FilterParam(
    soundHandle,
    super.busId,
    filterType,
    PitchShiftEnum.semitones.index,
    PitchShiftEnum.semitones.min,
    PitchShiftEnum.semitones.max,
  );

  /// Whether formants stay fixed while pitch transposes (>= 0.5 == on).
  ///
  /// Without this, a pitch shift also drags a voice's formants along with
  /// it, which is what makes even a modest shift sound like a different
  /// person ("chipmunk"/"monster"). This is a local patch — not present in
  /// upstream flutter_soloud, which never calls SignalsmithStretch's
  /// setFormantFactor — see third_party/flutter_soloud/src/filters/
  /// pitch_shift_filter.cpp. Formant analysis can misbehave on full music
  /// mixes rather than isolated vocals, hence exposing it as a toggle to
  /// A/B rather than always forcing it on.
  FilterParam formantPreserve({SoundHandle? soundHandle}) => FilterParam(
    soundHandle,
    super.busId,
    filterType,
    PitchShiftEnum.formantPreserve.index,
    PitchShiftEnum.formantPreserve.min,
    PitchShiftEnum.formantPreserve.max,
  );

  /// Adjust the play speed of a sound without changing the pitch of the audio.
  ///
  /// This is done by counteracting the change in pitch caused by changing the
  /// speed using the [shift] parameter.
  void timeStretch(SoundHandle soundHandle, double value) {
    // Adjust the play speed
    SoLoud.instance.setRelativePlaySpeed(soundHandle!, value);
    shift(soundHandle: soundHandle).value = 1.0 / value;
  }
}

class PitchShiftGlobal extends _PitchShiftInternal {
  const PitchShiftGlobal() : super(null, null);

  FilterParam get wet => FilterParam(
    null,
    null,
    filterType,
    PitchShiftEnum.wet.index,
    PitchShiftEnum.wet.min,
    PitchShiftEnum.wet.max,
  );

  /// The shift value of the pitch, where 1.0 means the pitch is not shifted.
  ///
  /// Note that both the [shift] and [semitones] parameters are acting to modify
  /// the pitch value, but using different scales. Changing this value will
  /// therefore adjust the [shift] parameter with:
  /// ```dart
  /// shift = pow(2., value / 12);
  /// ```
  FilterParam get shift => FilterParam(
    null,
    null,
    filterType,
    PitchShiftEnum.shift.index,
    PitchShiftEnum.shift.min,
    PitchShiftEnum.shift.max,
  );

  /// The number of semitones that the pitch is shifted.
  ///
  /// Note that both the [shift] and [semitones] parameters are acting to modify
  /// the pitch value, but using different scales. Changing this value will
  /// therefore adjust the [semitones] parameter with:
  /// ```dart
  /// semitones = 12 * log2f(value);
  /// ```
  FilterParam get semitones => FilterParam(
    null,
    null,
    filterType,
    PitchShiftEnum.semitones.index,
    PitchShiftEnum.semitones.min,
    PitchShiftEnum.semitones.max,
  );

  /// See [PitchShiftSingle.formantPreserve].
  FilterParam get formantPreserve => FilterParam(
    null,
    null,
    filterType,
    PitchShiftEnum.formantPreserve.index,
    PitchShiftEnum.formantPreserve.min,
    PitchShiftEnum.formantPreserve.max,
  );
}
