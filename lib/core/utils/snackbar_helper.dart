import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
 
class SnackbarHelper {
  SnackbarHelper._();
 
  static void showError(BuildContext context, String message) {
    _show(context, message: message, isError: true);
  }
 
  static void showSuccess(BuildContext context, String message) {
    _show(context, message: message, isError: false);
  }
 
  static void _show(
    BuildContext context, {
    required String message,
    required bool isError,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? AppColors.error : AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(16),
          duration: Duration(seconds: isError ? 4 : 3),
        ),
      );
  }
}