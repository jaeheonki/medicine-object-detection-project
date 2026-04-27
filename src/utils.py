# %% 구글 공유 데이터 다운로드
def download_data(extract_path="./data"):
    import gdown, zipfile
    gdown.download(f"https://drive.google.com/uc?id=1YgTmJPuppvarVklbkxAO7SK11fI-Siim", "알약데이터.zip", quiet=False)
    with zipfile.ZipFile("알약데이터.zip", "r") as zip_ref:
        zip_ref.extractall(extract_path)
    print("데이터 다운로드 완료!")

def download_more_data(label_out_dir, image_out_dir):
    import gdown, zipfile, shutil
    from pathlib import Path

    zip_path = Path("./more_data.zip")
    temp_dir = Path("./temp_download")

    gdown.download(f"https://drive.google.com/uc?id=1gq3W2g0GbOna9wd3kImSqXetBBLeLs-i", str(zip_path), quiet=False)
    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(temp_dir)

    src_folder = list(temp_dir.iterdir())[0]
    for file in (src_folder / "images").iterdir():
        shutil.move(str(file), str(Path(image_out_dir) / file.name))
    for file in (src_folder / "labels").iterdir():
        shutil.move(str(file), str(Path(label_out_dir) / file.name))

    zip_path.unlink()
    shutil.rmtree(temp_dir)
    print("추가 데이터 다운로드 완료!")
