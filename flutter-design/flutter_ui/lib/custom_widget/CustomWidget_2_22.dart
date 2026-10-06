import 'package:flutter/material.dart';
import 'package:flutter_ui/utils/pix_adapted_screen.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_2.dart';
import 'package:flutter_ui/utils/pix_extensions.dart';
import 'package:flutter_ui/utils/pix_base64_string.dart';

class CustomWidget_2_22 extends StatelessWidget {
 CustomWidget_2_22({super.key});
    late final ImageProvider _image_dnup2_23 = MemoryImage(imageStr_dnup2_23.decodeBase64Image());
  @override
  Widget build(BuildContext context) {
    return SizedBox(
          width: 390.w,
          child: SingleChildScrollView(
            clipBehavior: Clip.none,
            physics: NeverScrollableScrollPhysics(),
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: BoxConstraints(minWidth: 390.w, minHeight: 56.h),
              padding: EdgeInsets.only(left: 0.w,right: 0.w),
              child: Row(
                key: ValueKey("2:22"),
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 12.w,
                children: [
                  SizedBox(
                    height: 40.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 40.w, minHeight: 40.h),
                        decoration: BoxDecoration(image: DecorationImage(image: _image_dnup2_23, fit: BoxFit.fill),borderRadius: BorderRadius.circular(20.h),),
                        child: Column(
                          key: ValueKey("2:23"),
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 16.w,
                              height: 20.h,
                              child: Text("沐",
                                key: ValueKey("2:24"),
                                textAlign: TextAlign.left,
                                style: TextStyle(color: Color.fromRGBO(255, 255, 255,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 15.6.sp, letterSpacing: 0.w),),),
                          ],),),),),
                  SizedBox(
                    height: 37.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 131.w, minHeight: 37.h),
                        child: Column(
                          key: ValueKey("2:25"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2.h,
                          children: [
                            Container(
                              width: 102.w,
                              height: 20.h,
                              child: Text("早上好，沐瑾",
                                key: ValueKey("2:26"),
                                textAlign: TextAlign.left,
                                style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 16.6.sp, letterSpacing: 0.w),),),
                            Container(
                              width: 131.w,
                              height: 15.h,
                              child: Text("周四 · 10月30日 · 晴 18°",
                                key: ValueKey("2:27"),
                                textAlign: TextAlign.left,
                                style: TextStyle(color: Color.fromRGBO(140, 128, 121,1), fontFamily: "Inter", fontSize: 11.6.sp, letterSpacing: 0.w),),),
                          ],),),),),
                  Container(
                    width: 99.w,
                    height: 1.h,
                    child: Stack(
                      key: ValueKey("2:28"),
                      clipBehavior: Clip.none,),),
                  Container(
                    width: 36.w,
                    height: 36.h,
                    decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(12.h),border: Border.all(width: 1.w, color: Color.fromRGBO(240, 232, 224,1), ),),
                    child: Stack(
                      key: ValueKey("2:29"),
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          width: 18.w,
                          height: 18.h,
                          left: 9.w,
                          top: 9.h,
                          child: SvgPicture.asset("assets/images/bell.svg",
                            key: ValueKey("2:30"),),),
                        Positioned(
                          width: 8.w,
                          height: 8.h,
                          left: 23.w,
                          top: 6.h,
                          child: Container(
                            decoration: BoxDecoration(color: Color.fromRGBO(255, 140, 66,1),borderRadius: BorderRadius.circular(4.h),),
                            child: Stack(
                              key: ValueKey("2:33"),
                              clipBehavior: Clip.none,),),),
                      ],),),
                  SizedBox(
                    height: 36.h,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      child: Container(
                        constraints: BoxConstraints(minWidth: 36.w, minHeight: 36.h),
                        decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),borderRadius: BorderRadius.circular(12.h),border: Border.all(width: 1.w, color: Color.fromRGBO(240, 232, 224,1), ),),
                        child: Column(
                          key: ValueKey("2:34"),
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 18.w,
                              height: 18.h,
                              child: SvgPicture.asset("assets/images/settings.svg",
                                key: ValueKey("2:35"),),),
                          ],),),),),
                ],),),),);
  }
}
