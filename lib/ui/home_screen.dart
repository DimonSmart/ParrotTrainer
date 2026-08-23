import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../controllers/training_session_controller.dart';
import '../models/training_phrase.dart';
import '../services/sound_detector.dart';
import 'phrase_editor_screen.dart';
import 'voices_screen.dart';
import 'privacy_policy_screen.dart';
import 'activity_history_screen.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/app_strings.dart';
import 'package:package_info_plus/package_info_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.resumeForeground();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      controller.pauseForBackground();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      drawer: _AppDrawer(controller: controller),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              title: const Text(
                'Parrot Trainer',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              centerTitle: true,
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Text('🦜', style: TextStyle(fontSize: 38)),
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
              sliver: SliverList.list(
                children: [
                  if (!controller.microphoneAvailable)
                    _MicrophoneWarning(onRetry: _retryMicrophone),
                  _PhrasesCard(controller: controller),
                  _MicrophoneCard(controller: controller),
                  _IntervalsCard(controller: controller),
                  _ScheduleCard(controller: controller),
                  _VoicesCard(controller: controller),
                  _StatisticsCard(controller: controller),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _StartPanel(
        controller: controller,
        onToggle: _toggleTraining,
      ),
    ),
  );

  Future<void> _retryMicrophone() async {
    await controller.resumeForeground();
    if (!mounted || controller.microphoneAvailable) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.microphoneDenied)));
  }

  Future<void> _toggleTraining(bool enabled) async {
    if (!enabled) {
      await controller.stopTraining();
      return;
    }
    if (!controller.settings.isWithinScheduledHours(DateTime.now())) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.outsideSchedule)));
      return;
    }
    final started = await controller.startTraining();
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.cannotStartWithoutMicrophone)),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.onTap,
    this.trailing,
  });
  final String title;
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF207B25),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (trailing case final Widget trailing) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    ),
  );
}

class _PhrasesCard extends StatelessWidget {
  const _PhrasesCard({required this.controller});
  final AppController controller;
  Future<void> _open(BuildContext context) async {
    await controller.suspendMicrophoneCapture();
    if (!context.mounted) {
      await controller.resumeMicrophoneCapture();
      return;
    }
    try {
      final phrases = await Navigator.push<List<TrainingPhrase>>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PhraseEditorScreen(phrases: controller.settings.phrases),
        ),
      );
      if (phrases != null) {
        await controller.updateSettings(
          controller.settings.copyWith(phrases: phrases),
        );
      }
    } finally {
      await controller.resumeMicrophoneCapture();
    }
  }

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: context.strings.phrases,
    onTap: () => _open(context),
    trailing: IconButton(
      onPressed: () => _open(context),
      icon: const Icon(Icons.edit_outlined),
      tooltip: context.strings.edit,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...controller.settings.phrases
            .take(4)
            .map(
              (phrase) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(phrase.text, style: const TextStyle(fontSize: 18)),
              ),
            ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(context.strings.learningNow),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: controller.settings.focusPhraseId,
                hint: Text(context.strings.allPhrases),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(context.strings.allPhrases),
                  ),
                  ...controller.settings.phrases.map(
                    (phrase) => DropdownMenuItem(
                      value: phrase.id,
                      child: Text(phrase.text, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (id) => controller.updateSettings(
                  controller.settings.copyWith(
                    focusPhraseId: id,
                    clearFocusPhrase: id == null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _MicrophoneCard extends StatelessWidget {
  const _MicrophoneCard({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final level = dbToNormalized(controller.currentLevelDb);
    final threshold = dbToNormalized(controller.settings.soundThresholdDb);
    final detected = controller.session.isSoundActive;
    return _SectionCard(
      title: context.strings.microphone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.strings.soundLevel,
                style: const TextStyle(fontSize: 17),
              ),
              Text(
                '${(level * 100).round()}%',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _LevelMeter(level: level, threshold: threshold, detected: detected),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey(detected),
              children: [
                Icon(
                  detected ? Icons.hearing : Icons.hearing_disabled,
                  color: detected ? Colors.orange.shade800 : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  detected
                      ? context.strings.hearingSound
                      : context.strings.silence,
                  style: TextStyle(
                    fontWeight: detected ? FontWeight.w800 : FontWeight.normal,
                    color: detected
                        ? Colors.orange.shade900
                        : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.strings.threshold,
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                '${(threshold * 100).round()}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: threshold,
            onChanged: (value) => controller.updateSettings(
              controller.settings.copyWith(
                soundThresholdDb: normalizedToDb(value),
              ),
            ),
            divisions: 80,
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: controller.calibrating
                ? null
                : controller.calibrateMicrophone,
            icon: const Icon(Icons.tune),
            label: Text(
              controller.calibrating
                  ? context.strings.calibration(
                      controller.calibrationSecondsLeft,
                    )
                  : context.strings.calibrateMicrophone,
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelMeter extends StatelessWidget {
  const _LevelMeter({
    required this.level,
    required this.threshold,
    required this.detected,
  });
  final double level, threshold;
  final bool detected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const count = 32;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            children: List.generate(count, (index) {
              final active = (index + 1) / count <= level;
              final color = !active
                  ? Colors.grey.shade200
                  : index / count < .55
                  ? Colors.green.shade400
                  : index / count < .78
                  ? Colors.amber.shade500
                  : Colors.red.shade400;
              return Expanded(
                child: Container(
                  height: 28,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          Positioned(
            left: math.max(
              0,
              math.min(
                constraints.maxWidth - 2,
                constraints.maxWidth * threshold,
              ),
            ),
            top: -4,
            child: Container(
              width: 2,
              height: 36,
              color: detected ? Colors.red : Colors.black54,
            ),
          ),
        ],
      );
    },
  );
}

class _IntervalsCard extends StatelessWidget {
  const _IntervalsCard({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    return _SectionCard(
      title: context.strings.intervals,
      child: Column(
        children: [
          _DurationSlider(
            label: context.strings.minimumInterval,
            value: settings.minimumInterval.inSeconds.toDouble(),
            min: 1,
            max: 30,
            suffix: context.strings.seconds,
            divisions: 29,
            onChanged: (value) {
              final min = Duration(seconds: value.round());
              controller.updateSettings(
                settings.copyWith(
                  minimumInterval: min,
                  idlePromptMinInterval: settings.idlePromptMinInterval < min
                      ? min
                      : null,
                  idlePromptMaxInterval: settings.idlePromptMaxInterval < min
                      ? min
                      : null,
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.strings.startConversation,
                      style: TextStyle(fontSize: 16),
                    ),
                    Text(
                      '${settings.idlePromptMinInterval.inSeconds}–${settings.idlePromptMaxInterval.inSeconds} ${context.strings.seconds}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                RangeSlider(
                  values: RangeValues(
                    settings.idlePromptMinInterval.inSeconds.toDouble().clamp(
                      settings.minimumInterval.inSeconds.toDouble(),
                      180,
                    ),
                    settings.idlePromptMaxInterval.inSeconds.toDouble().clamp(
                      settings.minimumInterval.inSeconds.toDouble(),
                      180,
                    ),
                  ),
                  min: settings.minimumInterval.inSeconds.toDouble(),
                  max: 180,
                  divisions: (180 - settings.minimumInterval.inSeconds).clamp(
                    1,
                    179,
                  ),
                  onChanged: (range) => controller.updateSettings(
                    settings.copyWith(
                      idlePromptMinInterval: Duration(
                        seconds: range.start.round(),
                      ),
                      idlePromptMaxInterval: Duration(
                        seconds: range.end.round(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _DurationSlider(
            label: context.strings.responsePause,
            value: settings.silenceAfterSound.inMilliseconds / 1000,
            min: .5,
            max: 5,
            suffix: context.strings.seconds,
            divisions: 18,
            decimals: 1,
            onChanged: (value) => controller.updateSettings(
              settings.copyWith(
                silenceAfterSound: Duration(
                  milliseconds: (value * 1000).round(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.controller});

  final AppController controller;

  Future<void> _pickTime(BuildContext context, bool start) async {
    final settings = controller.settings;
    final minute = start
        ? settings.scheduleStartMinute
        : settings.scheduleEndMinute;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (selected == null) return;
    final value = selected.hour * 60 + selected.minute;
    await controller.updateSettings(
      settings.copyWith(
        scheduleStartMinute: start ? value : null,
        scheduleEndMinute: start ? null : value,
      ),
    );
  }

  String _format(BuildContext context, int minute) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        alwaysUse24HourFormat: true,
      );

  @override
  Widget build(BuildContext context) {
    final settings = controller.settings;
    return _SectionCard(
      title: context.strings.schedule,
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.strings.followSchedule),
            subtitle: Text(context.strings.scheduleDescription),
            value: settings.dailyScheduleEnabled,
            onChanged: (value) => controller.updateSettings(
              settings.copyWith(dailyScheduleEnabled: value),
            ),
          ),
          if (settings.dailyScheduleEnabled) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.strings.start),
              trailing: Text(_format(context, settings.scheduleStartMinute)),
              onTap: () => _pickTime(context, true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.strings.end),
              trailing: Text(_format(context, settings.scheduleEndMinute)),
              onTap: () => _pickTime(context, false),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.strings.allowScreenSleep),
            subtitle: Text(context.strings.screenSleepDescription),
            value: settings.allowScreenToSleep,
            onChanged: (value) => controller.updateSettings(
              settings.copyWith(allowScreenToSleep: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationSlider extends StatelessWidget {
  const _DurationSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.divisions,
    required this.onChanged,
    this.decimals = 0,
  });
  final String label, suffix;
  final double value, min, max;
  final int divisions, decimals;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Text(
              '${value.toStringAsFixed(decimals)} $suffix',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _VoicesCard extends StatelessWidget {
  const _VoicesCard({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final selected = controller.settings.selectedVoiceIds.length;
    return _SectionCard(
      title: context.strings.voiceAndSpeech,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VoicesScreen(controller: controller)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selected == 0
                      ? context.strings.defaultAndroidVoice
                      : context.strings.selectedVoices(selected),
                  style: const TextStyle(fontSize: 17),
                ),
              ),
              ...List.generate(
                math.min(3, math.max(1, selected)),
                (index) => Container(
                  margin: const EdgeInsets.only(left: 8),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: [
                      Colors.lightGreen.shade100,
                      Colors.amber.shade100,
                      Colors.lightBlue.shade100,
                    ][index],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: [
                      Colors.green.shade700,
                      Colors.orange.shade700,
                      Colors.blue.shade700,
                    ][index],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: controller.session.lastPhrase == null
                ? null
                : controller.markGoodAttempt,
            icon: const Icon(Icons.star_outline),
            label: Text(context.strings.goodAttempt),
          ),
        ],
      ),
    );
  }
}

class _StatisticsCard extends StatelessWidget {
  const _StatisticsCard({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final stats = controller.statistics;
    return _SectionCard(
      title: context.strings.statistics,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActivityHistoryScreen(controller: controller),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatBox(
              icon: Icons.chat_bubble,
              label: context.strings.phrasesSpoken,
              value: '${stats.totalPhrasesSpoken}',
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatBox(
              icon: Icons.flutter_dash,
              label: context.strings.responsesToChirps,
              value: '${stats.responsesToSound} (${stats.responsePercent}%)',
              color: Colors.lightBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.green.shade100),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 5),
        Text(label, textAlign: TextAlign.center, maxLines: 2),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

class _StartPanel extends StatelessWidget {
  const _StartPanel({required this.controller, required this.onToggle});
  final AppController controller;
  final ValueChanged<bool> onToggle;
  @override
  Widget build(BuildContext context) {
    final running = controller.session.isRunning;
    final progress = controller.session.nextSpeechProgress;
    final remaining = controller.session.timeUntilNextSpeech;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Material(
        color: running ? const Color(0xFF318E2D) : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(24),
        elevation: 8,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => onToggle(!running),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      running ? Icons.graphic_eq : Icons.mic_off,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            running
                                ? context.strings.programOn
                                : context.strings.programOff,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            controller.session.stateLabel,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: running,
                      onChanged: onToggle,
                      activeThumbColor: Colors.white,
                      activeTrackColor: Colors.lightGreenAccent.shade700,
                    ),
                  ],
                ),
                if (running) ...[
                  const SizedBox(height: 6),
                  _NextSpeechProgress(
                    progress: progress,
                    remaining: remaining,
                    isSpeaking:
                        controller.session.state == TrainingState.speaking,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NextSpeechProgress extends StatelessWidget {
  const _NextSpeechProgress({
    required this.progress,
    required this.remaining,
    required this.isSpeaking,
  });

  final double? progress;
  final Duration? remaining;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final label = isSpeaking
        ? context.strings.speaking
        : remaining == null
        ? context.strings.waitingForSilence
        : '${remaining!.inSeconds + 1} ${context.strings.seconds}';
    return Semantics(
      label: remaining == null
          ? label
          : context.strings.nextPhraseIn(remaining!.inSeconds + 1),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MicrophoneWarning extends StatelessWidget {
  const _MicrophoneWarning({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.orange.shade50,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(Icons.mic_off, color: Colors.deepOrange),
          const SizedBox(width: 10),
          Expanded(child: Text(context.strings.microphoneNeeded)),
          TextButton(onPressed: onRetry, child: Text(context.strings.retry)),
        ],
      ),
    ),
  );
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFFE8F5D8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('🦜', style: TextStyle(fontSize: 46)),
                  Text(
                    'Parrot Trainer',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(strings.about),
              onTap: () async {
                Navigator.pop(context);
                final info = await PackageInfo.fromPlatform();
                if (!context.mounted) return;
                showAboutDialog(
                  context: context,
                  applicationName: strings.appTitle,
                  applicationVersion: info.version,
                  children: [Text(strings.aboutDescription)],
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(strings.privacyPolicy),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PrivacyPolicyScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(strings.resetSettings),
              onTap: () async {
                Navigator.pop(context);
                await controller.resetSettings();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(strings.resetStatistics),
              onTap: () async {
                Navigator.pop(context);
                await controller.resetStatistics();
              },
            ),
          ],
        ),
      ),
    );
  }
}
