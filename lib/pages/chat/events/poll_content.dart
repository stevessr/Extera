import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'package:extera_next/generated/l10n/l10n.dart';
import 'package:extera_next/utils/poll_events.dart';
import 'package:extera_next/utils/stream_extension.dart';
import 'package:extera_next/widgets/matrix.dart';

class PollWidget extends StatefulWidget {
  final Color color;
  final Color linkColor;
  final double fontSize;
  final Event event;
  final Timeline timeline;

  const PollWidget(
    this.event, {
    required this.color,
    required this.linkColor,
    required this.fontSize,
    required this.timeline,
    super.key,
  });

  @override
  State<StatefulWidget> createState() => PollWidgetState();
}

class PollWidgetState extends State<PollWidget> {
  List<String> selectedAnswers = [];
  List<String> originalVote = []; // Store the original vote to detect changes
  bool hasVoted = false;
  bool isLoading = false;
  bool isVotesLoading = true;
  StreamSubscription<Event>? subscription;

  @override
  void initState() {
    super.initState();
    _loadPollData();
  }

  Future<void> _loadPollData() async {
    _checkExistingVote();
    await widget.event.fetchPollResponses(widget.timeline);
    if (mounted) {
      setState(() {
        isVotesLoading = false;
      });
    }
  }

  void _checkExistingVote() {
    final currentUserId = widget.event.room.client.userID;
    if (currentUserId == null) return;
    late final StreamSubscription<Event> sub;
    sub = Matrix.of(context).client.onTimelineEvent.stream.listen((event) {
      if (event.relationshipEventId != widget.event.eventId ||
          event.type != PollEventContent.responseType) {
        return;
      }
      _applyExistingVote(currentUserId);
    });
    subscription = sub;
    _applyExistingVote(currentUserId);
  }

  void _applyExistingVote(String currentUserId) {
    if (!mounted || hasVoted) return;
    final responses = widget.event.getPollResponses(widget.timeline);
    final answers = responses[currentUserId];
    if (answers == null) return;
    setState(() {
      selectedAnswers = answers.toList();
      originalVote = List.from(selectedAnswers);
      hasVoted = true;
    });
  }

  Future<void> _vote(List<String> answers) async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
    });

    try {
      await widget.event.answerPoll(answers);

      setState(() {
        selectedAnswers = answers;
        originalVote = List.from(answers); // Update original vote after voting
        hasVoted = true;
        isLoading = false;
        isVotesLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to vote: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onAnswerSelected(String answerId, bool selected) {
    final content =
        widget.event.content[PollEvents.pollStart] as Map<String, dynamic>;
    final maxSelections = content['max_selections'] as int? ?? 1;

    setState(() {
      if (maxSelections == 1) {
        // Single selection - replace current selection
        selectedAnswers = selected ? [answerId] : [];
      } else {
        // Multiple selection
        if (selected) {
          if (selectedAnswers.length < maxSelections) {
            selectedAnswers.add(answerId);
          }
        } else {
          selectedAnswers.remove(answerId);
        }
      }
    });
  }

  bool _isPollEnded() => widget.event.getPollHasBeenEnded(widget.timeline);

  bool _shouldShowResults() {
    final content =
        widget.event.content[PollEvents.pollStart] as Map<String, dynamic>;
    final kind = content['kind'] as String?;
    final isDisclosed = kind == 'org.matrix.msc3381.poll.disclosed';
    final isEnded = _isPollEnded();

    return isDisclosed || isEnded;
  }

  double _getAnswerPercentage(
    Map<String, int> results,
    int totalVotes,
    String answerId,
  ) {
    if (totalVotes == 0) return 0.0;
    return (results[answerId]?.toDouble() ?? 0) / totalVotes.toDouble();
  }

  // Check if the current selection is different from the original vote
  bool _hasSelectionChanged() {
    if (selectedAnswers.length != originalVote.length) return true;

    // Sort both lists to compare regardless of order
    final sortedSelected = List.from(selectedAnswers)..sort();
    final sortedOriginal = List.from(originalVote)..sort();

    for (var i = 0; i < sortedSelected.length; i++) {
      if (sortedSelected[i] != sortedOriginal[i]) return true;
    }

    return false;
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final event = widget.event;
    final content = event.content[PollEvents.pollStart] as Map<String, dynamic>;
    final question =
        content['question']?['m.text'] as String? ??
        content['question']?['org.matrix.msc1767.text'] as String? ??
        content['question']?['body'] as String? ??
        'Poll';
    final List<dynamic> answers = content['answers'] ?? [];
    final maxSelections = content['max_selections'] as int? ?? 1;
    final kind = content['kind'] as String?;

    final shouldShowResults = _shouldShowResults();
    final responses = event.getPollResponses(widget.timeline);
    var totalVotes = 0;
    final results = <String, int>{};
    for (final answers in responses.values) {
      for (final answer in answers) {
        results[answer] = (results[answer] ?? 0) + 1;
      }
      totalVotes++;
    }
    final isEnded = _isPollEnded();
    final canVote = !isEnded && !isLoading;
    final hasChanged = _hasSelectionChanged();

    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question with Material 3 styling
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 16),
            child: Text(
              question,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: widget.fontSize + 1,
                color: widget.color,
                letterSpacing: 0.15,
              ),
            ),
          ),

          // answers
          StreamBuilder(
            key: ValueKey(event.eventId),
            stream: client.onTimelineEvent.stream
                .where(
                  (s) =>
                      s.type == "org.matrix.msc3381.poll.response" &&
                      s.relationshipEventId == event.eventId,
                )
                .rateLimit(const Duration(seconds: 1)),
            builder: (context, _) {
              if (isVotesLoading) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  ...answers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final answer = entry.value as Map<String, dynamic>;
                    final answerId = answer['id'] as String;
                    final answerText =
                        answer['m.text'] as String? ??
                        answer['org.matrix.msc1767.text'] as String? ??
                        'Answer ${index + 1}';
                    final isSelected = selectedAnswers.contains(answerId);
                    final percentage = _getAnswerPercentage(
                      results,
                      totalVotes,
                      answerId,
                    );
                    // final voteCount = pollResults?[answerId] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: shouldShowResults && !isVotesLoading
                            ? widget.color.withValues(alpha: 0.04)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: canVote
                              ? () => _onAnswerSelected(answerId, !isSelected)
                              : null,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : widget.color.withValues(alpha: 0.12),
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Stack(
                              children: [
                                // Progress bar background
                                if (shouldShowResults && !isVotesLoading)
                                  Positioned.fill(
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: percentage,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? theme.colorScheme.primary
                                                    .withValues(alpha: 0.12)
                                              : widget.color.withValues(
                                                  alpha: 0.08,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                // Answer content
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  child: Row(
                                    children: [
                                      // Selection indicator
                                      if (canVote) ...[
                                        if (maxSelections == 1)
                                          RadioGroup<bool>(
                                            groupValue: isSelected,
                                            onChanged: (_) => _onAnswerSelected(
                                              answerId,
                                              !isSelected,
                                            ),
                                            child: Radio<bool>(
                                              value: true,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                          )
                                        else
                                          Checkbox(
                                            value: isSelected,
                                            onChanged: (_) => _onAnswerSelected(
                                              answerId,
                                              !isSelected,
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                        const SizedBox(width: 8),
                                      ] else if (isSelected) ...[
                                        Icon(
                                          Icons.check_circle,
                                          color: theme.colorScheme.primary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                      ] else if (!canVote) ...[
                                        const SizedBox(width: 4),
                                      ],

                                      Expanded(
                                        child: Text(
                                          answerText,
                                          style: TextStyle(
                                            fontSize: widget.fontSize,
                                            color: widget.color,
                                            fontWeight: isSelected
                                                ? FontWeight.w500
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ),

                                      // Vote count and percentage
                                      if (shouldShowResults &&
                                          !isVotesLoading) ...[
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: widget.color.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '${(percentage * 100).toStringAsFixed(0)}%',
                                            style: TextStyle(
                                              fontSize: widget.fontSize - 2,
                                              color: widget.color,
                                              fontWeight: FontWeight.w600,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),

          const SizedBox(height: 8),

          // Vote button and info
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (canVote && selectedAnswers.isNotEmpty)
                // Show "Change Vote" button only when selection has changed
                if (!hasVoted || (hasVoted && hasChanged))
                  FilledButton.icon(
                    onPressed: isLoading ? null : () => _vote(selectedAnswers),
                    icon: isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            hasVoted ? Icons.edit : Icons.how_to_vote,
                            size: 18,
                          ),
                    label: Text(
                      hasVoted
                          ? L10n.of(context).changeVote
                          : L10n.of(context).vote,
                    ),
                  ),

              // Poll metadata chips
              _PollInfoChip(
                icon: maxSelections == 1
                    ? Icons.radio_button_checked
                    : Icons.check_box,
                label: maxSelections == 1
                    ? L10n.of(context).singleChoice
                    : L10n.of(context).multipleChoice,
                color: widget.color,
                fontSize: widget.fontSize,
              ),

              _PollInfoChip(
                icon: kind == 'org.matrix.msc3381.poll.undisclosed'
                    ? Icons.visibility_off
                    : Icons.visibility,
                label: kind == 'org.matrix.msc3381.poll.undisclosed'
                    ? L10n.of(context).anonymousPoll
                    : L10n.of(context).publicPoll,
                color: widget.color,
                fontSize: widget.fontSize,
              ),

              _PollInfoChip(
                icon: isEnded ? Icons.check_circle : Icons.timer,
                label: isEnded
                    ? L10n.of(context).endedPoll
                    : L10n.of(context).activePoll,
                color: widget.color,
                fontSize: widget.fontSize,
              ),
            ],
          ),

          if (selectedAnswers.isNotEmpty && maxSelections > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: widget.color.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    L10n.of(
                      context,
                    ).choicesSelected(selectedAnswers.length, maxSelections),
                    style: TextStyle(
                      fontSize: widget.fontSize - 1,
                      color: widget.color.withValues(alpha: 0.7),
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PollInfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double fontSize;

  const _PollInfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.12), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize - 2,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
