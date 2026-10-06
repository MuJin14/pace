import 'package:flutter/material.dart';
import 'package:flutter_ui/utils/pix_adapted_screen.dart';
import 'package:flutter_svg/svg.dart';

class CustomWidget_2_2 extends StatelessWidget {
 CustomWidget_2_2({super.key});
  
  @override
  Widget build(BuildContext context) {
    return SizedBox(
          width: 390.w,
          child: SingleChildScrollView(
            clipBehavior: Clip.none,
            physics: NeverScrollableScrollPhysics(),
            scrollDirection: Axis.horizontal,
            child: Container(
              constraints: BoxConstraints(minWidth: 390.w, minHeight: 62.h),
              padding: EdgeInsets.only(left: 0.w,right: 0.w),
              child: Row(
                key: ValueKey("2:2"),
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32.w,
                    height: 19.h,
                    child: Text("9:41",
                      key: ValueKey("2:3"),
                      textAlign: TextAlign.left,
                      style: TextStyle(color: Color.fromRGBO(36, 31, 28,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 14.6.sp, letterSpacing: 0.w),),),
                  SizedBox(
                    width: 60.w,
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      physics: NeverScrollableScrollPhysics(),
                      scrollDirection: Axis.horizontal,
                      child: Container(
                        constraints: BoxConstraints(minWidth: 60.w, minHeight: 16.h),
                        child: Row(
                          key: ValueKey("2:4"),
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          spacing: 6.w,
                          children: [
                            Container(
                              width: 16.w,
                              height: 16.h,
                              child: SvgPicture.asset("assets/images/signal.svg",
                                key: ValueKey("2:5"),),),
                            Container(
                              width: 16.w,
                              height: 16.h,
                              child: SvgPicture.asset("assets/images/wifi.svg",
                                key: ValueKey("2:11"),),),
                            Container(
                              width: 16.w,
                              height: 16.h,
                              child: Stack(
                                key: ValueKey("2:16"),
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    width: 1.33.w,
                                    height: 4.h,
                                    left: 6.67.w,
                                    top: 6.67.h,
                                    child: SvgPicture.asset("assets/images/Vector_2_17.svg",
                                      key: ValueKey("2:17"),),),
                                  Positioned(
                                    width: 1.33.w,
                                    height: 4.h,
                                    left: 9.33.w,
                                    top: 6.67.h,
                                    child: SvgPicture.asset("assets/images/Vector_2_18.svg",
                                      key: ValueKey("2:18"),),),
                                  Positioned(
                                    width: 1.33.w,
                                    height: 4.h,
                                    left: 14.67.w,
                                    top: 6.67.h,
                                    child: SvgPicture.asset("assets/images/Vector_2_19.svg",
                                      key: ValueKey("2:19"),),),
                                  Positioned(
                                    width: 1.33.w,
                                    height: 4.h,
                                    left: 4.w,
                                    top: 6.67.h,
                                    child: SvgPicture.asset("assets/images/Vector_2_20.svg",
                                      key: ValueKey("2:20"),),),
                                  Positioned(
                                    width: 10.67.w,
                                    height: 8.h,
                                    left: 1.33.w,
                                    top: 4.h,
                                    child: Container(
                                      key: ValueKey("2:21"),
                                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(1.33.h),border: Border.all(width: 1.33.w, color: Color.fromRGBO(36, 31, 28,1), strokeAlign: BorderSide.strokeAlignCenter),),),),
                                ],),),
                          ],),),),),
                ],),),),);
  }
}
