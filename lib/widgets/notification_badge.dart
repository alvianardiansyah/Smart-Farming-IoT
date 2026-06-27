import 'package:flutter/material.dart';

class NotificationBadge extends StatelessWidget {
  final int count;

  const NotificationBadge({Key? key, required this.count}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 8,
      top: 8,
      child: Container(
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(10),
        ),
        constraints: BoxConstraints(
          minWidth: 16,
          minHeight: 16,
        ),
        child: Text(
          count > 9 ? '9+' : count.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
