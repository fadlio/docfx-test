import os

def get_summary(file_path) -> tuple[str, str, str]:
    with open(file_path, 'r') as file:
        lines = file.readlines()
        summary_lines = []
        class_name = ""
        namespace = ""
        reading_summary = False
        for line in lines:
            if "<summary>" in line:
                reading_summary = True
            if "</summary>" in line:
                reading_summary = False
            if "namespace" in line:
                namespace = line.strip()
                if namespace.startswith("namespace Instaclause.Domain."):
                    namespace = namespace.replace("namespace Instaclause.Domain.", "")[:-1]
                else:
                    namespace = ""
            if line.startswith("public class"):
                class_name = line.strip()
                class_name = class_name.replace("public class", "")
                class_name = class_name.split(":")[0].strip()
                break
            if reading_summary:
                summary_lines.append(line.strip()[4:])
        return class_name, namespace, " ".join(summary_lines[1:])
    


if __name__ == "__main__":
    summaries = []
    # traverse the Instaclause.Domain recursively folder and extract the class name and summary of each file
    folder_path = "/home/lio/Projects/2na8/instaclause/Instaclause/src/Instaclause.Domain"
    for root, dirs, files in os.walk(folder_path):
        for file in files:
            if file.endswith(".cs"):
                file_path = os.path.join(root, file)
                class_name, namespace, summary = get_summary(file_path)
                if len(namespace) > 0 and len(class_name) > 0:
                    summaries.append((class_name, namespace, summary))
    
    # group the summaries by namespace
    summaries.sort(key=lambda x: x[1])
    grouped_summaries = {}
    for class_name, namespace, summary in summaries:
        if namespace not in grouped_summaries:
            grouped_summaries[namespace] = []
        grouped_summaries[namespace].append((class_name, summary))

    # save data to a md file
    with open("domain.md", "w") as file:
        for namespace, summaries in grouped_summaries.items():
            file.write(f"## {namespace}\n")
            for class_name, summary in summaries:
                file.write(f"### {class_name}\n")
                file.write(f"{summary}\n\n")