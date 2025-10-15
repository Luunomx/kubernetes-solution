db = db.getSiblingDB('BulletinBoardDb');

db.Posts.insertMany([
    { 
        "Id": 1, 
        "Name": "Learn Kubernetes", 
        "Message": "Start with kubectl and minikube basics.", 
        "CreationTime": new Date() 
    },
    { 
        "Id": 2, 
        "Name": "Deploy MongoDB", 
        "Message": "Set up persistent volume and service for MongoDB.", 
        "CreationTime": new Date() 
    }
]);

print("Database initialized with sample posts!");
