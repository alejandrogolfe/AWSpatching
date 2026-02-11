import boto3
import os
import tempfile
from PIL import Image

s3 = boto3.client("s3")


def main():
    bucket = os.environ["BUCKET"]
    input_key = os.environ["INPUT_KEY"]

    # Derive output key: input/foo.jpg -> output/foo.jpg
    filename = os.path.basename(input_key)
    output_key = f"output/{filename}"

    print(f"Processing: s3://{bucket}/{input_key}")
    print(f"Destination: s3://{bucket}/{output_key}")

    with tempfile.TemporaryDirectory() as tmpdir:
        input_path = os.path.join(tmpdir, filename)
        output_path = os.path.join(tmpdir, f"flipped_{filename}")

        # Download from S3
        print("Downloading image...")
        s3.download_file(bucket, input_key, input_path)

        # Flip horizontally (mirror left <-> right)
        print("Flipping image horizontally...")
        with Image.open(input_path) as img:
            flipped = img.transpose(Image.FLIP_LEFT_RIGHT)
            flipped.save(output_path)
            print(f"Image size: {img.size}, mode: {img.mode}")

        # Upload result to S3
        print("Uploading result...")
        s3.upload_file(
            output_path,
            bucket,
            output_key,
            ExtraArgs={"ContentType": "image/jpeg"},
        )

    print(f"Done! Result saved to s3://{bucket}/{output_key}")


if __name__ == "__main__":
    main()
