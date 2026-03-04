import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

class HighscoresScreen extends StatefulWidget {
  final String? highlightDocId;
  const HighscoresScreen({super.key, this.highlightDocId});

  @override
  State<HighscoresScreen> createState() => _HighscoresScreenState();
}

class _GemDisplay extends StatelessWidget {
  final int gems;
  const _GemDisplay({required this.gems});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Row(
        children: [
          const Icon(Icons.diamond, color: Colors.cyanAccent, size: 24),
          const SizedBox(width: 4),
          Text(
            "$gems",
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _HighscoresScreenState extends State<HighscoresScreen> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  bool _showGemAnim = false;
  bool _hasScrolled = false;

  void _scrollToNewScore(List<QueryDocumentSnapshot> docs) {
    if (widget.highlightDocId == null || _hasScrolled) return;
    _hasScrolled = true;

    int index = docs.indexWhere((doc) => doc.id == widget.highlightDocId);

    if (index != -1) {
      Future.delayed(const Duration(milliseconds: 600), () {
        _itemScrollController.scrollTo(
          index: index,
          duration: const Duration(seconds: 2),
          curve: Curves.easeInOutCubic,
        );

        // Trigger the "+ Gems" visual after the pan completes
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showGemAnim = true);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    
    return Scaffold(
      appBar: AppBar(
        title: const Text("Rankings"),
        actions: [
          // Gem Counter in AppBar
          if (uid.isNotEmpty) // <--- ADD THIS CHECK
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
              builder: (context, snapshot) {
                // If it's loading or has no data, show 0 or a placeholder
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const _GemDisplay(gems: 0);
                }
                
                final userData = snapshot.data?.data() as Map<String, dynamic>?;
                final int gems = userData?['gems'] ?? 0;
                return _GemDisplay(gems: gems);
              },
            )
          else
            const _GemDisplay(gems: 0), // Show 0 gems for Guests
        ],
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('memory_highscores')
                .orderBy('high_score', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              _scrollToNewScore(docs);

              return ScrollablePositionedList.separated(
                itemScrollController: _itemScrollController,
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                itemCount: docs.length,
                separatorBuilder: (context, index) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final bool isNewScore = docs[index].id == widget.highlightDocId;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    decoration: BoxDecoration(
                      color: isNewScore ? Colors.orange.withOpacity(0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isNewScore ? Colors.orange : Colors.blue.shade100,
                        child: Text("${index + 1}", style: TextStyle(color: isNewScore ? Colors.white : Colors.blue)),
                      ),
                      title: Text(
                        data['player_name'] ?? 'Anonymous',
                        style: TextStyle(fontWeight: isNewScore ? FontWeight.w900 : FontWeight.normal),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isNewScore && _showGemAnim)
                            const _GemPopAnimation(), // The +Gems visual
                          Text(
                            "${data['high_score']}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// Borderless, floating animation for the gem reward
class _GemPopAnimation extends StatelessWidget {
  const _GemPopAnimation();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: const Duration(seconds: 1),
      tween: Tween<double>(begin: 0.0, end: 1.0),
      builder: (context, double value, child) {
        return Transform.translate(
          offset: Offset(0, -20 * value), // Floats upward
          child: Opacity(
            opacity: 1.0 - value, // Fades out
            child: const Row(
              children: [
                Icon(Icons.add, color: Colors.green, size: 16),
                Icon(Icons.diamond, color: Colors.cyanAccent, size: 16),
                SizedBox(width: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}