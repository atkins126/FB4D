{******************************************************************************}
{                                                                              }
{  Delphi FB4D Library                                                         }
{  Copyright (c) 2018-2023 Christoph Schneider                                 }
{  Schneider Infosystems AG, Switzerland                                       }
{  https://github.com/SchneiderInfosystems/FB4D                                }
{                                                                              }
{******************************************************************************}
{                                                                              }
{  Licensed under the Apache License, Version 2.0 (the "License");             }
{  you may not use this file except in compliance with the License.            }
{  You may obtain a copy of the License at                                     }
{                                                                              }
{      http://www.apache.org/licenses/LICENSE-2.0                              }
{                                                                              }
{  Unless required by applicable law or agreed to in writing, software         }
{  distributed under the License is distributed on an "AS IS" BASIS,           }
{  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.    }
{  See the License for the specific language governing permissions and         }
{  limitations under the License.                                              }
{                                                                              }
{******************************************************************************}

unit FB4D.SelfRegistrationFra;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  Vcl.ExtCtrls, Vcl.WinXCtrls, Vcl.Mask, Vcl.Imaging.jpeg,
  FB4D.Interfaces, Vcl.ExtDlgs;

type
  TOnGetAuth = function : IFirebaseAuthentication of object;
  TOnGetStorage = function : IFirebaseStorage of object;
  TFraSelfRegistration = class(TFrame)
    AniIndicator: TActivityIndicator;
    pnlStatus: TPanel;
    gdpAcitivityInd: TGridPanel;
    pnlCheckRegistered: TPanel;
    btnCheckEMail: TButton;
    btnResetPwd: TButton;
    btnSignIn: TButton;
    btnSignUp: TButton;
    edtEMail: TLabeledEdit;
    pnlPassword: TPanel;
    edtPassword: TLabeledEdit;
    lblStatus: TLabel;
    pnlDisplayName: TPanel;
    edtDisplayName: TLabeledEdit;
    btnRegisterDisplayName: TButton;
    imgProfile: TImage;
    btnLoadProfile: TButton;
    OpenPictureDialog: TOpenPictureDialog;
    procedure edtEMailChange(Sender: TObject);
    procedure btnCheckEMailClick(Sender: TObject);
    procedure btnSignInClick(Sender: TObject);
    procedure btnSignUpClick(Sender: TObject);
    procedure btnResetPwdClick(Sender: TObject);
    procedure btnRegisterDisplayNameClick(Sender: TObject);
    procedure btnLoadProfileClick(Sender: TObject);
  public const
    cDefaultProfileImgSize = 300; // 300x300 pixels
    cDefaultStoragePathForProfileImg = 'userProfiles';
  private
    fAuth: IFirebaseAuthentication;
    fOnUserLogin: TOnUserResponse;
    fOnGetAuth: TOnGetAuth;
    fAllowSelfRegistration: boolean;
    fRequireVerificatedEMail: boolean;
    fRegisterDisplayName: boolean;
    fRegisterProfileImg: boolean;
    fStorage: IFirebaseStorage;
    fOnGetStorage: TOnGetStorage;
    fStoragePath: string;
    fReqInfo: string;
    fInfo: string;
    fUser: IFirebaseUser;
    fTokenRefreshed: boolean;
    fProfileLoadStream: TMemoryStream;
    fProfileImgSize: integer;
    fProfileURL: string;
    fProfileImg: TJPEGImage;
    fDefaultProfileImg: TJPEGImage;
    procedure StartTokenReferesh(const LastToken: string);
    procedure OnFetchProviders(const EMail: string; IsRegistered: boolean;
      Providers: TStrings);
    procedure OnFetchProvidersError(const Info, ErrMsg: string);
    procedure OnResetPwd(const Info: string; Response: IFirebaseResponse);
    procedure OnUserError(const Info, ErrMsg: string);
    procedure OnUserResponse(const Info: string; User: IFirebaseUser);
    procedure OnTokenRefresh(TokenRefreshed: boolean);
    procedure OnGetUserData(FirebaseUserList: TFirebaseUserList);
    procedure OnVerificationMailSent(const RequestID: string;
      Response: IFirebaseResponse);
    procedure OnChangedProfile(const RequestID: string;
      Response: IFirebaseResponse);
    procedure OnProfileImgUpload(Obj: IStorageObject);
    procedure OnProfileImgError(const RequestID, ErrMsg: string);
    procedure StartDownloadProfileImg(PhotoURL: string);
    procedure OnProfileDownload(const DownloadURL: string);
    function GetProfileImg: TJPEGImage;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Initialize(Auth: IFirebaseAuthentication;
      OnUserLogin: TOnUserResponse; const LastRefreshToken: string = '';
      const LastEMail: string = ''; AllowSelfRegistration: boolean = true;
      RequireVerificatedEMail: boolean = false;
      RegisterDisplayName: boolean = false);
    procedure InitializeAuthOnDemand(OnGetAuth: TOnGetAuth;
      OnUserLogin: TOnUserResponse; const LastRefreshToken: string = '';
      const LastEMail: string = ''; AllowSelfRegistration: boolean = true;
      RequireVerificatedEMail: boolean = false;
      RegisterDisplayName: boolean = false);
    procedure RequestProfileImg(OnGetStorage: TOnGetStorage;
      const StoragePath: string = cDefaultStoragePathForProfileImg;
      ProfileImgSize: integer = cDefaultProfileImgSize);
    procedure StartEMailEntering;
    procedure InformDelayedStart(const Msg: string);
    procedure StopDelayedStart;
    function GetEMail: string;
    property ProfileImg: TJPEGImage read GetProfileImg;
    property ProfileURL: string read fProfileURL;
  end;

implementation

uses
  REST.Types,
  FB4D.Helpers;

{$R *.dfm}

// Install the following Storage Rule when using method RequestProfileImg:
// rules_version = '2';
// service firebase.storage {
//   match /b/{bucket}/o {
//     match /userProfiles/{userID} {
//       allow read: if request.auth != null;
//       allow write: if request.auth.uid == userID;
//     }
//   }
// }

resourcestring
  rsEnterEMail = 'Enter your e-mail address for sign-in or registration';
  rsWait = 'Please wait for Firebase';
  rsEnterPassword = 'Enter your password for registration';
  rsSetupPassword = 'Setup a new password for future registrations';
  rsNotRegisteredEMail = 'The entered e-mail is not registered';
  rsPleaseCheckEMail = 'Please check your e-mail inbox to renew your password';
  rsLoggedIn = 'Successful logged in';
  rsPleaseCheckEMailForVerify =
    'Please check your e-mail inbox to confirm your email address';
  rsWriteProfileData = 'Your %s will be registrated';
  rsUserError = 'Access of user data failed: %s';
  rsProfileLoadErr = 'Load of your profile photo is failed: %s';


constructor TFraSelfRegistration.Create(AOwner: TComponent);
begin
  inherited;
  edtDisplayName.Visible := false;
  btnRegisterDisplayName.Visible := false;
  imgProfile.Visible := false;
  fProfileURL := '';
  fProfileImg := nil;
  fTokenRefreshed := false;
  fStorage := nil;
  fDefaultProfileImg := TJPEGImage.Create;
  fDefaultProfileImg.Assign(imgProfile.Picture.Bitmap);
end;

destructor TFraSelfRegistration.Destroy;
begin
  fProfileLoadStream.Free;
  fDefaultProfileImg.Free;
  fProfileImg.Free;
  inherited;
end;

procedure TFraSelfRegistration.Initialize(Auth: IFirebaseAuthentication;
  OnUserLogin: TOnUserResponse; const LastRefreshToken, LastEMail: string;
  AllowSelfRegistration, RequireVerificatedEMail, RegisterDisplayName: boolean);
begin
  fAuth := Auth;
  fOnUserLogin := OnUserLogin;
  fOnGetAuth := nil;
  edtEMail.Text := LastEMail;
  fAllowSelfRegistration := AllowSelfRegistration;
  fRequireVerificatedEMail := RequireVerificatedEMail;
  fRegisterDisplayName := RegisterDisplayName;
  if LastRefreshToken.IsEmpty then
    StartEMailEntering
  else
    StartTokenReferesh(LastRefreshToken);
end;

procedure TFraSelfRegistration.InitializeAuthOnDemand(OnGetAuth: TOnGetAuth;
  OnUserLogin: TOnUserResponse; const LastRefreshToken, LastEMail: string;
  AllowSelfRegistration, RequireVerificatedEMail, RegisterDisplayName: boolean);
begin
  fAuth := nil;
  fOnUserLogin := OnUserLogin;
  fOnGetAuth := OnGetAuth;
  edtEMail.Text := LastEMail;
  fAllowSelfRegistration := AllowSelfRegistration;
  fRequireVerificatedEMail := RequireVerificatedEMail;
  fRegisterDisplayName := RegisterDisplayName;
  if LastRefreshToken.IsEmpty then
    StartEMailEntering
  else
    StartTokenReferesh(LastRefreshToken);
end;

procedure TFraSelfRegistration.RequestProfileImg(OnGetStorage: TOnGetStorage;
  const StoragePath: string; ProfileImgSize: integer);
begin
  fRegisterProfileImg := true;
  fOnGetStorage := OnGetStorage;
  fStoragePath := StoragePath;
  fProfileImgSize := ProfileImgSize;
end;

procedure TFraSelfRegistration.StartEMailEntering;
begin
  fInfo := '';
  edtEMail.Visible := true;
  btnCheckEMail.Visible := true;
  btnCheckEMail.Enabled := TFirebaseHelpers.IsEMailAdress(edtEMail.Text);
  lblStatus.Caption := rsEnterEMail;
  btnSignIn.Visible := false;
  btnResetPwd.Visible := false;
  btnSignUp.Visible := false;
  edtPassword.Visible := false;
  edtDisplayName.Visible := false;
  btnRegisterDisplayName.Visible := false;
  imgProfile.Visible := false;
  edtEMail.SetFocus;
end;

procedure TFraSelfRegistration.edtEMailChange(Sender: TObject);
begin
  if edtPassword.Visible then
  begin
    lblStatus.Caption := rsEnterEMail;
    edtPassword.Visible := false;
    btnCheckEMail.Visible := true;
    btnSignUp.Visible := false;
    btnSignIn.Visible := false;
    btnResetPwd.Visible := false;
  end;
  btnCheckEMail.Enabled := TFirebaseHelpers.IsEMailAdress(edtEMail.Text);
end;

procedure TFraSelfRegistration.btnCheckEMailClick(Sender: TObject);
begin
  if not assigned(fAuth) and assigned(fOnGetAuth) then
    fAuth := fOnGetAuth;
  Assert(assigned(fAuth), 'Auth is not initialized');
  fAuth.FetchProvidersForEMail(trim(edtEmail.Text), OnFetchProviders,
    OnFetchProvidersError);
  AniIndicator.Enabled := true;
  AniIndicator.Visible := true;
  btnCheckEMail.Enabled := false;
  lblStatus.Caption := rsWait;
end;

procedure TFraSelfRegistration.OnFetchProviders(const EMail: string;
  IsRegistered: boolean; Providers: TStrings);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  if IsRegistered then
  begin
    btnSignUp.Visible := false;
    btnSignIn.Visible := true;
    btnSignIn.Enabled := true;
    btnResetPwd.Visible := true;
    btnResetPwd.Enabled := true;
    lblStatus.Caption := rsEnterPassword;
    edtPassword.Text := '';
    edtPassword.Visible := true;
    edtPassword.SetFocus;
    btnCheckEMail.Visible := false;
  end
  else if fAllowSelfRegistration then
  begin
    btnSignUp.Visible := true;
    btnSignUp.Enabled := true;
    btnSignIn.Visible := false;
    btnResetPwd.Visible := false;
    lblStatus.Caption := rsSetupPassword;
    edtPassword.Text := '';
    edtPassword.Visible := true;
    edtPassword.SetFocus;
    btnCheckEMail.Visible := false;
  end else begin
    lblStatus.Caption := rsNotRegisteredEMail;
    edtEMail.SetFocus;
  end;
end;

procedure TFraSelfRegistration.OnFetchProvidersError(const Info, ErrMsg: string);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  lblStatus.Caption := Info + ': ' + ErrMsg;
  btnCheckEMail.Enabled := true;
end;

procedure TFraSelfRegistration.btnSignInClick(Sender: TObject);
begin
  fAuth.SignInWithEmailAndPassword(trim(edtEmail.Text), edtPassword.Text,
    OnUserResponse, OnUserError);
  AniIndicator.Enabled := true;
  AniIndicator.Visible := true;
  btnSignIn.Enabled := false;
  btnResetPwd.Enabled := false;
  lblStatus.Caption := rsWait;
end;

procedure TFraSelfRegistration.btnSignUpClick(Sender: TObject);
begin
  fAuth.SignUpWithEmailAndPassword(trim(edtEmail.Text), edtPassword.Text,
    OnUserResponse, OnUserError);
  AniIndicator.Enabled := true;
  AniIndicator.Visible := true;
  btnSignUp.Enabled := false;
  lblStatus.Caption := rsWait;
end;

procedure TFraSelfRegistration.btnResetPwdClick(Sender: TObject);
begin
  fAuth.SendPasswordResetEMail(trim(edtEMail.Text), OnResetPwd, OnUserError);
  AniIndicator.Enabled := true;
  AniIndicator.Visible := true;
  btnSignIn.Enabled := false;
  btnResetPwd.Enabled := false;
  lblStatus.Caption := rsWait;
end;

procedure TFraSelfRegistration.OnResetPwd(const Info: string; Response: IFirebaseResponse);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  btnSignIn.Enabled := true;
  if Response.StatusOk then
    lblStatus.Caption := rsPleaseCheckEMail
  else
    lblStatus.Caption := Response.ErrorMsgOrStatusText;
end;

procedure TFraSelfRegistration.StartTokenReferesh(const LastToken: string);
begin
  if not assigned(fAuth) and assigned(fOnGetAuth) then
    fAuth := fOnGetAuth;
  Assert(assigned(fAuth), 'Auth is not initialized');
  AniIndicator.Enabled := true;
  AniIndicator.Visible := true;
  edtEMail.Visible := false;
  btnCheckEMail.Visible := false;
  lblStatus.Caption := rsWait;
  btnSignIn.Visible := false;
  btnResetPwd.Visible := false;
  btnSignUp.Visible := false;
  edtPassword.Visible := false;
  fReqInfo := 'AfterTokenRefresh';
  fAuth.RefreshToken(LastToken, OnTokenRefresh, OnUserError);
end;

procedure TFraSelfRegistration.OnTokenRefresh(TokenRefreshed: boolean);
begin
  if TokenRefreshed then
    fAuth.GetUserData(OnGetUserData, OnUserError)
  else
    StartEMailEntering;
end;

procedure TFraSelfRegistration.OnGetUserData(FirebaseUserList: TFirebaseUserList);
var
  User: IFirebaseUser;
begin
  if FirebaseUserList.Count = 1 then
  begin
    User := FirebaseUserList[0];
    if fRequireVerificatedEMail then
      if User.IsEMailVerified <> tsbTrue then
      begin
        fAuth.SendEmailVerification(OnVerificationMailSent, OnUserError);
        exit;
      end;
    OnUserResponse(fReqInfo, User);
  end else
    StartEMailEntering;
end;

procedure TFraSelfRegistration.OnUserError(const Info, ErrMsg: string);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  StartEMailEntering;
  lblStatus.Caption := Info + ': ' + ErrMsg;
end;

procedure TFraSelfRegistration.OnUserResponse(const Info: string;
  User: IFirebaseUser);
const
  cReqInfo4Photo = 'GetUserDataForPhoto';
var
  WaitForDisplayNameOrProfile: boolean;
begin
  if fRequireVerificatedEMail then
    case User.IsEMailVerified of
      tsbUnspecified:
        begin
          fReqInfo := 'GetUserData';
          fAuth.GetUserData(OnGetUserData, OnUserError);
          exit;
        end;
      tsbFalse:
        begin
          fAuth.SendEmailVerification(OnVerificationMailSent, OnUserError);
          exit;
        end;
    end;
  if fRegisterProfileImg and not User.IsPhotoURLAvailable and
    not SameText(Info, cReqInfo4Photo) then
  begin
    fReqInfo := cReqInfo4Photo;
    fAuth.GetUserData(OnGetUserData, OnUserError);
    exit;
  end;
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  edtEMail.Visible := false;
  edtPassword.Visible := false;
  btnSignIn.Visible := false;
  btnSignUp.Visible := false;
  btnResetPwd.Visible := false;
  fInfo := Info;
  if assigned(fUser) and (fUser.UID <> User.UID) then
  begin
    fProfileURL := '';
    imgProfile.Picture.Bitmap.Assign(fDefaultProfileImg);
  end;
  fUser := User;
  WaitForDisplayNameOrProfile := false;
  if fRegisterDisplayName and User.IsDisplayNameAvailable and
    not User.DisplayName.IsEmpty then
  begin
    lblStatus.visible := false;
    edtDisplayName.Visible := true;
    edtDisplayName.Text := User.DisplayName;
    btnRegisterDisplayName.Visible := true;
  end;
  if fRegisterProfileImg and User.IsPhotoURLAvailable and
    not User.PhotoURL.IsEmpty and fProfileURL.IsEmpty then
  begin
    StartDownloadProfileImg(User.PhotoURL);
    WaitForDisplayNameOrProfile := true;
  end
  else if fRegisterProfileImg and
    (not User.IsPhotoURLAvailable or User.PhotoURL.IsEmpty) then
  begin
    imgProfile.Visible := true;
    WaitForDisplayNameOrProfile := true;
  end;
  if fRegisterDisplayName and
    (not User.IsDisplayNameAvailable or User.DisplayName.IsEmpty) then
  begin
    lblStatus.visible := false;
    edtDisplayName.Visible := true;
    edtDisplayName.SetFocus;
    btnRegisterDisplayName.Visible := true;
    imgProfile.Visible := fRegisterProfileImg;
    WaitForDisplayNameOrProfile := true;
  end;
  if assigned(fOnUserLogin) and not WaitForDisplayNameOrProfile then
  begin
    lblStatus.Caption := rsLoggedIn;
    fOnUserLogin(fInfo, fUser);
  end;
end;

function TFraSelfRegistration.GetEMail: string;
begin
  result := trim(edtEmail.Text);
end;

function TFraSelfRegistration.GetProfileImg: TJPEGImage;
begin
  if assigned(fProfileImg) then
    result := fProfileImg
  else
    result := fDefaultProfileImg;
end;

procedure TFraSelfRegistration.OnVerificationMailSent(const RequestID: string;
  Response: IFirebaseResponse);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  lblStatus.Caption := rsPleaseCheckEMailForVerify;
  btnSignIn.Enabled := true;
end;

procedure TFraSelfRegistration.btnRegisterDisplayNameClick(Sender: TObject);
begin
  edtDisplayName.Visible := false;
  btnRegisterDisplayName.Visible := false;
  lblStatus.Caption :=
    Format(rsWriteProfileData, [edtDisplayName.EditLabel.Caption]);
  fAuth.ChangeProfile('', '', edtDisplayName.Text, fProfileURL,
    OnChangedProfile, OnUserError);
end;

procedure TFraSelfRegistration.OnChangedProfile(const RequestID: string;
  Response: IFirebaseResponse);
begin
  fAuth.GetUserData(OnGetUserData, OnUserError);
end;

procedure TFraSelfRegistration.StartDownloadProfileImg(PhotoURL: string);
begin
  FreeAndNil(fProfileLoadStream);
  imgProfile.Visible := true;
  fProfileLoadStream := TMemoryStream.Create;
  TFirebaseHelpers.SimpleDownload(PhotoURL, fProfileLoadStream,
    OnProfileDownload, OnProfileImgError);
  AniIndicator.Enabled := true;
  AniIndicator.Visible := true;
end;

procedure TFraSelfRegistration.btnLoadProfileClick(Sender: TObject);
var
  Bmp: TJPEGImage;
  Siz: integer;
  SrcRct, DstRct: TRect;
  Ofs: integer;
begin
  if OpenPictureDialog.Execute(Handle) then
  begin
    Bmp := TJPEGImage.Create;
    fProfileImg := TJPEGImage.Create;
    FreeAndNil(fProfileLoadStream);
    fProfileLoadStream := TMemoryStream.Create;
    try
      Bmp.LoadFromFile(OpenPictureDialog.FileName);
      // Crop square image from center
      if Bmp.Width > Bmp.Height then
      begin
        Siz := Bmp.Height;
        Ofs := (Bmp.Width - Siz) div 2;
        SrcRct := Rect(Ofs, 0, Ofs + Siz, Siz);
      end else begin
        Siz := Bmp.Width;
        Ofs := (Bmp.Height - Siz) div 2;
        SrcRct := Rect(0, Ofs, Siz, Ofs + Siz);
      end;
      fProfileImg.Width := fProfileImgSize;
      fProfileImg.Height := fProfileImgSize;
      DstRct := Rect(0, 0, fProfileImgSize, fProfileImgSize);
      fProfileImg.Canvas.StretchDraw(SrcRct, Bmp);
      imgProfile.Picture.Bitmap.Assign(fProfileImg);
      fStorage := fOnGetStorage;
      imgProfile.Picture.SaveToStream(fProfileLoadStream);
      fProfileLoadStream.Position := 0;
      fStorage.UploadFromStream(fProfileLoadStream,
        fStoragePath + '/' + fUser.UID, TRESTContentType.ctIMAGE_JPEG,
        OnProfileImgUpload, OnProfileImgError);
      btnLoadProfile.Enabled := false;
      AniIndicator.Enabled := true;
      AniIndicator.Visible := true;
    finally
      Bmp.Free;
    end;
  end;
end;

procedure TFraSelfRegistration.OnProfileImgUpload(Obj: IStorageObject);
begin
  FreeAndNil(fProfileLoadStream);
  fProfileURL := Obj.DownloadUrl;
  fAuth.ChangeProfile('', '', edtDisplayName.Text, fProfileURL,
    OnChangedProfile, OnUserError);
end;

procedure TFraSelfRegistration.OnProfileDownload(const DownloadURL: string);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  fProfileURL := DownloadURL;
  fProfileImg := TJPEGImage.Create;
  fProfileImg.LoadFromStream(fProfileLoadStream);
  imgProfile.Picture.Assign(fProfileImg);
  FreeAndNil(fProfileLoadStream);
  if assigned(fOnGetStorage) then
    fOnGetStorage(); // Side effect disable Bucket edit box
  if assigned(fOnUserLogin) and fTokenRefreshed then
  begin
    lblStatus.Caption := rsLoggedIn;
    TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(100);
        TThread.Queue(nil,
          procedure
          begin
            fOnUserLogin(fInfo, fUser);
          end);
      end).Start;
  end else if fRegisterDisplayName then
    btnRegisterDisplayName.Visible := true;
end;

procedure TFraSelfRegistration.OnProfileImgError(const RequestID,
  ErrMsg: string);
begin
  AniIndicator.Enabled := false;
  AniIndicator.Visible := false;
  lblStatus.Caption := Format(rsProfileLoadErr, [ErrMsg]);
  FreeAndNil(fProfileLoadStream);
end;

procedure TFraSelfRegistration.InformDelayedStart(const Msg: string);
begin
  edtDisplayName.Visible := false;
  btnRegisterDisplayName.Visible := false;
  imgProfile.Visible := false;
  AniIndicator.Visible := true;
  AniIndicator.Enabled := true;
  lblStatus.visible := true;
  lblStatus.Caption := Msg;
  {$IFDEF DEBUG}
  TFirebaseHelpers.Log('FraSelfRegistration.InformDelayedStart: ' + Msg);
  {$ENDIF}
end;

procedure TFraSelfRegistration.StopDelayedStart;
begin
  AniIndicator.Visible := false;
  AniIndicator.Enabled := false;
  lblStatus.Caption := '';
  {$IFDEF DEBUG}
  TFirebaseHelpers.Log('FraSelfRegistration.StopDelayedStart');
  {$ENDIF}
end;

end.
