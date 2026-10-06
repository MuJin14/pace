import 'package:flutter/material.dart';
import 'package:flutter_ui/utils/pix_adapted_screen.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_2.dart';
import 'package:flutter_ui/utils/pix_extensions.dart';
import 'package:flutter_ui/utils/pix_base64_string.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_22.dart';
import 'package:flutter_ui/custom_widget/CustomWidget_2_38.dart';

class CustomWidget_2_172 extends StatelessWidget {
 CustomWidget_2_172({super.key});
    late final ImageProvider _image_dnup2_23 = MemoryImage(imageStr_dnup2_23.decodeBase64Image());
  late final ImageProvider _image_cqzu2_39 = MemoryImage(imageStr_cqzu2_39.decodeBase64Image());
  late final ImageProvider _image_tyje2_123 = MemoryImage(imageStr_tyje2_123.decodeBase64Image());
  late final ImageProvider _image_mvlh2_201 = MemoryImage(imageStr_mvlh2_201.decodeBase64Image());
  @override
  Widget build(BuildContext context) {
    return Container(
          width: 390.w,
          height: 100.h,
          child: Stack(
            key: ValueKey("2:172"),
            clipBehavior: Clip.none,
            children: [
              Positioned(
                width: 390.w,
                height: 84.h,
                left: 0.w,
                top: 16.h,
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  physics: NeverScrollableScrollPhysics(),
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 390.w, minHeight: 84.h),
                    padding: EdgeInsets.only(left: 10.w,right: 10.w, top: 10.h,bottom: 18.h),
                    decoration: BoxDecoration(color: Color.fromRGBO(255, 255, 255,1),boxShadow: [BoxShadow(color: Color.fromRGBO(36, 31, 28,0.101961),offset: Offset(0.w, -4.w),blurRadius: 16.w,)],),
                    child: Row(
                      key: ValueKey("2:173"),
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 38.h,
                          child: SingleChildScrollView(
                            clipBehavior: Clip.none,
                            physics: NeverScrollableScrollPhysics(),
                            child: Container(
                              constraints: BoxConstraints(minWidth: 74.5.w, minHeight: 38.h),
                              child: Column(
                                key: ValueKey("2:174"),
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                spacing: 4.h,
                                children: [
                                  Container(
                                    width: 20.w,
                                    height: 20.h,
                                    child: SvgPicture.asset("assets/images/home.svg",
                                      key: ValueKey("2:175"),),),
                                  Container(
                                    width: 22.w,
                                    height: 14.h,
                                    child: Text("首页",
                                      key: ValueKey("2:178"),
                                      textAlign: TextAlign.left,
                                      style: TextStyle(color: Color.fromRGBO(255, 122, 46,1), fontFamily: "Inter", fontWeight: FontWeight.bold, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                ],),),),),
                        SizedBox(
                          height: 38.h,
                          child: SingleChildScrollView(
                            clipBehavior: Clip.none,
                            physics: NeverScrollableScrollPhysics(),
                            child: Container(
                              constraints: BoxConstraints(minWidth: 74.5.w, minHeight: 38.h),
                              child: Column(
                                key: ValueKey("2:179"),
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                spacing: 4.h,
                                children: [
                                  Container(
                                    width: 20.w,
                                    height: 20.h,
                                    child: SvgPicture.asset("assets/images/trophy.svg",
                                      key: ValueKey("2:180"),),),
                                  Container(
                                    width: 22.w,
                                    height: 14.h,
                                    child: Text("排行",
                                      key: ValueKey("2:187"),
                                      textAlign: TextAlign.left,
                                      style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                ],),),),),
                        Container(
                          width: 72.w,
                          height: 1.h,
                          child: Stack(
                            key: ValueKey("2:188"),
                            clipBehavior: Clip.none,),),
                        SizedBox(
                          height: 38.h,
                          child: SingleChildScrollView(
                            clipBehavior: Clip.none,
                            physics: NeverScrollableScrollPhysics(),
                            child: Container(
                              constraints: BoxConstraints(minWidth: 74.5.w, minHeight: 38.h),
                              child: Column(
                                key: ValueKey("2:189"),
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                spacing: 4.h,
                                children: [
                                  Container(
                                    width: 20.w,
                                    height: 20.h,
                                    child: SvgPicture.asset("assets/images/users.svg",
                                      key: ValueKey("2:190"),),),
                                  Container(
                                    width: 22.w,
                                    height: 14.h,
                                    child: Text("社区",
                                      key: ValueKey("2:195"),
                                      textAlign: TextAlign.left,
                                      style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                ],),),),),
                        SizedBox(
                          height: 38.h,
                          child: SingleChildScrollView(
                            clipBehavior: Clip.none,
                            physics: NeverScrollableScrollPhysics(),
                            child: Container(
                              constraints: BoxConstraints(minWidth: 74.5.w, minHeight: 38.h),
                              child: Column(
                                key: ValueKey("2:196"),
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                spacing: 4.h,
                                children: [
                                  Container(
                                    width: 20.w,
                                    height: 20.h,
                                    child: SvgPicture.asset("assets/images/user.svg",
                                      key: ValueKey("2:197"),),),
                                  Container(
                                    width: 22.w,
                                    height: 14.h,
                                    child: Text("我的",
                                      key: ValueKey("2:200"),
                                      textAlign: TextAlign.left,
                                      style: TextStyle(color: Color.fromRGBO(181, 170, 162,1), fontFamily: "Inter", fontWeight: FontWeight.w500, fontSize: 10.6.sp, letterSpacing: 0.w),),),
                                ],),),),),
                      ],),),),),
              Positioned(
                width: 60.w,
                height: 60.h,
                left: 165.w,
                top: 0.h,
                child: SingleChildScrollView(
                  clipBehavior: Clip.none,
                  physics: NeverScrollableScrollPhysics(),
                  child: Container(
                    constraints: BoxConstraints(minWidth: 60.w, minHeight: 60.h),
                    decoration: BoxDecoration(image: DecorationImage(image: _image_mvlh2_201, fit: BoxFit.fill),borderRadius: BorderRadius.circular(30.h),boxShadow: [BoxShadow(color: Color.fromRGBO(255, 122, 46,0.34902),offset: Offset(0.w, 6.w),blurRadius: 16.w,)],),
                    child: Column(
                      key: ValueKey("2:201"),
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 26.w,
                          height: 26.h,
                          child: SvgPicture.asset("assets/images/footprints.svg",
                            key: ValueKey("2:202"),),),
                      ],),),),),
            ],),);
  }
}
