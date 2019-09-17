package com.dmc.mediaPickerPlugin;

import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.graphics.Point;
import android.media.ExifInterface;
import android.media.ThumbnailUtils;
import android.net.Uri;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Base64;
import android.util.Log;

import com.dmcbig.mediapicker.PickerActivity;
import com.dmcbig.mediapicker.PickerConfig;
import com.dmcbig.mediapicker.TakePhotoActivity;
import com.dmcbig.mediapicker.entity.Media;
import com.dmcbig.mediapicker.utils.FileUtils;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FilenameFilter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;


/**
 * This class echoes a string called from JavaScript.
 */
public class MediaPicker extends CordovaPlugin {
    private  CallbackContext callback;
    private  int thumbnailQuality=50;
    private  int quality=100;//default original
    private  int thumbnailW=200;
    private  int thumbnailH=200;

    private static String UPLOAD_DIR = "/upload-dir";

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        getPublicArgs(args);

        if (action.equals("getMedias")) {
            this.getMedias(args, callbackContext);
            return true;
        }else if(action.equals("takePhoto")){
            this.takePhoto(args, callbackContext);
            return true;
        }else if(action.equals("photoLibrary")){
            this.getMedias(args, callbackContext);
            return true;
        }else if(action.equals("extractThumbnail")){
            this.extractThumbnail(args, callbackContext);
            return true;
        }else if(action.equals("compressImage")){
            this.compressImage(args, callbackContext);
            return true;
        }else if(action.equals("fileToBlob")){
            this.fileToBlob(args.getString(0), callbackContext);
            return true;
        }else if(action.equals("getExifForKey")){
            this.getExifForKey(args.getString(0),args.getString(1),callbackContext);
            return true;
        }else if(action.equals("getFileInfo")){
            this.getFileInfo(args,callbackContext);
            return true;
        }
        return false;
    }

    private void takePhoto(JSONArray args, CallbackContext callbackContext) {
        this.callback=callbackContext;
        Intent intent =new Intent(cordova.getActivity(), TakePhotoActivity.class); //Take a photo with a camera
        this.cordova.startActivityForResult(this,intent,200);
    }

    private void getMedias(JSONArray args, CallbackContext callbackContext) {
        File cacheDir = getTempDirectory();
        cacheDir.delete();

        this.callback=callbackContext;
        Intent intent =new Intent(cordova.getActivity(), PickerActivity.class);
        intent.putExtra(PickerConfig.MAX_SELECT_COUNT,10);  //default 40 (Optional)
        JSONObject jsonObject=new JSONObject();
        if (args != null && args.length() > 0) {
            try {
                jsonObject=args.getJSONObject(0);
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                intent.putExtra(PickerConfig.SELECT_MODE,jsonObject.getInt("selectMode"));//default image and video (Optional)
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                intent.putExtra(PickerConfig.MAX_SELECT_SIZE,jsonObject.getLong("maxSelectSize")); //default 180MB (Optional)
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                intent.putExtra(PickerConfig.MAX_SELECT_COUNT,jsonObject.getInt("maxSelectCount"));  //default 40 (Optional)
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                ArrayList<Media> select= new ArrayList<Media>();
                JSONArray jsonArray=jsonObject.getJSONArray("defaultSelectedList");
                for(int i=0;i<jsonArray.length();i++){
                    select.add(new Media(jsonArray.getString(i), "", 0, 0,0,0,""));
                }
                intent.putExtra(PickerConfig.DEFAULT_SELECTED_LIST,select); // (Optional)
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
        this.cordova.startActivityForResult(this,intent,200);
    }

    public  void getPublicArgs(JSONArray args){
        JSONObject jsonObject=new JSONObject();
        if (args != null && args.length() > 0) {
            try {
                jsonObject = args.getJSONObject(0);
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                thumbnailQuality = jsonObject.getInt("thumbnailQuality");
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                thumbnailW = jsonObject.getInt("thumbnailW");
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                thumbnailH = jsonObject.getInt("thumbnailH");
            } catch (Exception e) {
                e.printStackTrace();
            }
            try {
                quality = jsonObject.getInt("quality");
            } catch (Exception e) {
                e.printStackTrace();
            }
        }
    }


    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent intent) {
        super.onActivityResult(requestCode, resultCode, intent);
        try {
            if(requestCode==200&&resultCode==PickerConfig.RESULT_CODE){
                final ArrayList<Media> select=intent.getParcelableArrayListExtra(PickerConfig.EXTRA_RESULT);
                final JSONArray jsonArray=new JSONArray();

                cordova.getThreadPool().execute(new Runnable() {
                    public void run() {
                        try {
                            int index=0;

                            for(Media media:select){
                                media.path = MediaPicker.this.imageToTmp(media.path);

                                JSONObject object=new JSONObject();
                                object.put("path",media.path);
                                object.put("uri",Uri.fromFile(new File(media.path)));//Uri.fromFile(file).toString() || [NSURL fileURLWithPath:filePath] absoluteString]
                                object.put("size",media.size);
                                object.put("name",media.name);
                                object.put("index",index);
                                object.put("mediaType",media.mediaType==3?"video":"image");
                                jsonArray.put(object);
                                index++;

                                if (media.mediaType != 3) {
                                    MediaPicker.this.createImageThumbnail(media);
                                }
                            }

                            MediaPicker.this.callback.success(jsonArray);
                        } catch (JSONException | IOException e) {
                            e.printStackTrace();
                        }
                    }
                });
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private File getTempDirectory() {
        String path;

        // SD Card Mounted
        if (Environment.getExternalStorageState().equals(Environment.MEDIA_MOUNTED) && Environment.isExternalStorageRemovable()) {
            path = Environment.getExternalStorageDirectory().getAbsolutePath() +
                    "/Android/data/" + cordova.getActivity().getPackageName() + "/cache"  + UPLOAD_DIR;
        } else {
            // Use internal storage
            path = cordova.getActivity().getCacheDir().getPath() + UPLOAD_DIR;
        }

        // Create the cache directory if it doesn't exist
        File cache = new File(path);
        cache.mkdirs();
        return cache;
    }

    private String imageToTmp(String path) throws IOException {
        File cacheDir = getTempDirectory();

        File pickedFile = new File(path);

        int filenamePos = path.lastIndexOf("/");
        String filename = filenamePos > -1 ? path.substring(filenamePos + 1) : "hoopop_media";

        File copiedFile = new File(cacheDir.getPath() + "/" + filename);
        copiedFile.createNewFile();

        try (InputStream in = new FileInputStream(pickedFile)) {
            try (OutputStream out = new FileOutputStream(copiedFile)) {
                byte[] buf = new byte[1024];
                int len;
                while ((len = in.read(buf)) > 0) {
                    out.write(buf, 0, len);
                }
            }
        }

        return copiedFile.getPath();
    }

    private void createImageThumbnail(Media media) {
        File image = new File(media.path);
        int degree = getBitmapRotate(media.path);

        ByteArrayOutputStream baos = new ByteArrayOutputStream();

        BitmapFactory.Options bitmapOptions = new BitmapFactory.Options();
        Bitmap bitmap = BitmapFactory.decodeFile(image.getAbsolutePath(), bitmapOptions);
        bitmap = rotatingImage(degree, bitmap);
        bitmap = getScaledDownBitmap(bitmap, 650, false);
        bitmap.compress(Bitmap.CompressFormat.JPEG, 90, baos);

        int index = media.path.lastIndexOf("/") + 1;
        String directory = media.path.substring(0, index);
        String filename = media.path.substring(index);

        try {
            File file = new File(directory, "thumbnail_" + filename);
            file.createNewFile();

            FileOutputStream fos = new FileOutputStream(file);
            fos.write(baos.toByteArray());
            fos.flush();
            fos.close();

        } catch (Exception e) {
            MediaPicker.this.callback.error("createImageThumbnail error"+e);
            e.printStackTrace();
        }
    }

    /**
     * @param bitmap the Bitmap to be scaled
     * @param threshold the maximum dimension (either width or height) of the scaled bitmap
     * @param isNecessaryToKeepOrig is it necessary to keep the original bitmap? If not recycle the original bitmap to prevent memory leak.
     * */
    private Bitmap getScaledDownBitmap(Bitmap bitmap, int threshold, boolean isNecessaryToKeepOrig){
        int width = bitmap.getWidth();
        int height = bitmap.getHeight();
        int newWidth = width;
        int newHeight = height;

        if(width > height && width > threshold){
            newWidth = threshold;
            newHeight = (int)(height * (float)newWidth/width);
        }

        if(width > height && width <= threshold){
            //the bitmap is already smaller than our required dimension, no need to resize it
            return bitmap;
        }

        if(width < height && height > threshold){
            newHeight = threshold;
            newWidth = (int)(width * (float)newHeight/height);
        }

        if(width < height && height <= threshold){
            //the bitmap is already smaller than our required dimension, no need to resize it
            return bitmap;
        }

        if(width == height && width > threshold){
            newWidth = threshold;
            newHeight = newWidth;
        }

        if(width == height && width <= threshold){
            //the bitmap is already smaller than our required dimension, no need to resize it
            return bitmap;
        }

        return getResizedBitmap(bitmap, newWidth, newHeight, isNecessaryToKeepOrig);
    }

    private Bitmap getResizedBitmap(Bitmap bm, int newWidth, int newHeight, boolean isNecessaryToKeepOrig) {
        int width = bm.getWidth();
        int height = bm.getHeight();
        float scaleWidth = ((float) newWidth) / width;
        float scaleHeight = ((float) newHeight) / height;
        // CREATE A MATRIX FOR THE MANIPULATION
        Matrix matrix = new Matrix();
        // RESIZE THE BIT MAP
        matrix.postScale(scaleWidth, scaleHeight);

        // "RECREATE" THE NEW BITMAP
        Bitmap resizedBitmap = Bitmap.createBitmap(bm, 0, 0, width, height, matrix, true);
        if(!isNecessaryToKeepOrig){
            bm.recycle();
        }
        return resizedBitmap;
    }

    public void extractThumbnail(JSONArray args, CallbackContext callbackContext){
        JSONObject jsonObject=new JSONObject();
        if (args != null && args.length() > 0) {
            try {
                jsonObject = args.getJSONObject(0);
            } catch (JSONException e) {
                e.printStackTrace();
            }
            try {
                thumbnailQuality = jsonObject.getInt("thumbnailQuality");
            } catch (JSONException e) {
                e.printStackTrace();
            }
            try {
                String path =jsonObject.getString("path");
                jsonObject.put("exifRotate",getBitmapRotate(path));
                int mediatype = "video".equals(jsonObject.getString("mediaType"))?3:1;
                jsonObject.put("thumbnailBase64",extractThumbnail(path,mediatype,thumbnailQuality));
            } catch (Exception e) {
                e.printStackTrace();
            }
            callbackContext.success(jsonObject);
        }
    }

    public  String extractThumbnail(String path,int mediaType,int quality) {
        String encodedImage = null;
        try {
            Bitmap thumbImage;
            if (mediaType == 3) {
                thumbImage = ThumbnailUtils.createVideoThumbnail(path, MediaStore.Images.Thumbnails.MINI_KIND);
            } else {
                thumbImage = ThumbnailUtils.extractThumbnail(BitmapFactory.decodeFile(path), thumbnailW, thumbnailH);
            }
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            thumbImage.compress(Bitmap.CompressFormat.JPEG, quality, baos);
            byte[] imageBytes = baos.toByteArray();
            encodedImage = Base64.encodeToString(imageBytes, Base64.NO_WRAP);
            baos.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return encodedImage;
    }

    public void  compressImage( JSONArray args, CallbackContext callbackContext){
        this.callback=callbackContext;
        try {
            JSONObject jsonObject = args.getJSONObject(0);
            String path = jsonObject.getString("path");
            int quality=jsonObject.getInt("quality");
            if(quality<100) {
                File file = compressImage(path, quality);
                jsonObject.put("path", file.getPath());
                jsonObject.put("uri", Uri.fromFile(new File(file.getPath())));
                jsonObject.put("size", file.length());
                jsonObject.put("name", file.getName());
                callbackContext.success(jsonObject);
            }else{
                callbackContext.success(jsonObject);
            }
        } catch (Exception e) {
            callbackContext.error("compressImage error"+e);
            e.printStackTrace();
        }
    }

    public void  getFileInfo( JSONArray args, CallbackContext callbackContext){
        this.callback=callbackContext;
        try {
            String type=args.getString(1);
            File file;
            if("uri".equals(type)){
                file=new File(FileHelper.getRealPath(args.getString(0),cordova));
            }else{
                file=new File(args.getString(0));
            }
            JSONObject jsonObject=new JSONObject();
            jsonObject.put("path", file.getPath());
            jsonObject.put("uri", Uri.fromFile(new File(file.getPath())));
            jsonObject.put("size", file.length());
            jsonObject.put("name", file.getName());
            String mimeType = FileHelper.getMimeType(jsonObject.getString("uri"),cordova);
            String mediaType = mimeType.indexOf("video")!=-1?"video":"image";
            jsonObject.put("mediaType",mediaType);
            callbackContext.success(jsonObject);
        } catch (Exception e) {
            callbackContext.error("getFileInfo error"+e);
            e.printStackTrace();
        }
    }

    public File compressImage(String path,int quality){
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        String compFileName="dmcMediaPickerCompress"+System.currentTimeMillis()+".jpg";
        File file= new File(cordova.getActivity().getExternalCacheDir(),compFileName);
        rotatingImage(getBitmapRotate(path),BitmapFactory.decodeFile(path)).compress(Bitmap.CompressFormat.JPEG, quality, baos);
        try {
            FileOutputStream fos = new FileOutputStream(file);
            fos.write(baos.toByteArray());
            fos.flush();
            fos.close();
        } catch (Exception e) {
            MediaPicker.this.callback.error("compressImage error"+e);
            e.printStackTrace();
        }
        return  file;
    }

    public  int getBitmapRotate(String path) {
        int degree = 0;
        try {
            ExifInterface exifInterface = new ExifInterface(path);
            int orientation = exifInterface.getAttributeInt(ExifInterface.TAG_ORIENTATION,ExifInterface.ORIENTATION_NORMAL);
            switch (orientation) {
                case ExifInterface.ORIENTATION_ROTATE_90:
                    degree = 90;
                    break;
                case ExifInterface.ORIENTATION_ROTATE_180:
                    degree = 180;
                    break;
                case ExifInterface.ORIENTATION_ROTATE_270:
                    degree = 270;
                    break;
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return degree;
    }

    private static Bitmap rotatingImage(int angle, Bitmap bitmap) {
        //rotate image
        Matrix matrix = new Matrix();
        matrix.postRotate(angle);

        //create a new image
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix,
                true);
    }


    public  byte[] extractThumbnailByte(String path,int mediaType,int quality) {

        try {
            Bitmap thumbImage;
            if (mediaType == 3) {
                thumbImage = ThumbnailUtils.createVideoThumbnail(path, MediaStore.Images.Thumbnails.MINI_KIND);
            } else {
                thumbImage = ThumbnailUtils.extractThumbnail(BitmapFactory.decodeFile(path), thumbnailW, thumbnailH);
            }
            ByteArrayOutputStream baos = new ByteArrayOutputStream();
            thumbImage.compress(Bitmap.CompressFormat.JPEG, quality, baos);
            return baos.toByteArray();
        } catch (Exception e) {
            e.printStackTrace();
            return null;
        }
    }

    public  void getExifForKey(String path,String tag, CallbackContext callbackContext) {
        try {
            ExifInterface exifInterface = new ExifInterface(path);
            String object = exifInterface.getAttribute(tag);
            callbackContext.success(object);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    public  String fileToBase64(String path) {
        byte[] data = null;
        try {
            BufferedInputStream in = new BufferedInputStream(new FileInputStream(path));
            data = new byte[in.available()];
            in.read(data);
            in.close();
        } catch (IOException e) {
            e.printStackTrace();
        }
        return Base64.encodeToString(data, Base64.NO_WRAP);
    }

    public  void fileToBlob(String path, CallbackContext callbackContext) {
        byte[] data = null;
        try {
            BufferedInputStream in = new BufferedInputStream(new FileInputStream(path));
            data = new byte[in.available()];
            in.read(data);
            in.close();
        } catch (IOException e) {
            callbackContext.error("fileToBlob "+e);
            e.printStackTrace();
        }
        callbackContext.success(data);
    }
}
