import 'package:e1547/follow/follow.dart';
import 'package:e1547/interface/interface.dart';
import 'package:e1547/post/post.dart';
import 'package:flutter/material.dart';

class FollowsTimelinePage extends StatefulWidget {
  const FollowsTimelinePage({super.key});

  @override
  State<FollowsTimelinePage> createState() => _FollowsTimelinePageState();
}

class _FollowsTimelinePageState extends State<FollowsTimelinePage> {
  @override
  Widget build(BuildContext context) {
    return RouterDrawerEntry<FollowsTimelinePage>(
      child: PostProvider.builder(
        create: (context, client) => FollowTimelineController(client: client),
        child: Consumer<PostController>(
          builder: (context, controller, child) => PostsPage(
            appBar: const DefaultAppBar(
              title: Text('Timeline'),
              actions: [ContextDrawerButton()],
            ),
            controller: controller,
            drawerActions: const [FollowEditingTile()],
            displayType: PostDisplayType.timeline,
            canSelect: false,
          ),
        ),
      ),
    );
  }
}
