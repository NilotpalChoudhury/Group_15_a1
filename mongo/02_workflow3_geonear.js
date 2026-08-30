use("bitestream");

const restaurantLongitude = 78.4867;
const restaurantLatitude = 17.3850;

const results = db.driverPings.aggregate([
    {
        $geoNear: {
            near: {
                type: "Point",
                coordinates: [
                    restaurantLongitude,
                    restaurantLatitude
                ]
            },
            key: "location",
            distanceField: "distance_from_restaurant",
            maxDistance: 5000,
            spherical: true,
            query: {
                active: true
            }
        }
    },
    {
        $addFields: {
            distance_km: {
                $divide: [
                    "$distance_from_restaurant",
                    1000
                ]
            }
        }
    },
    {
        $project: {
            _id: 0,
            driver_id: 1,
            active: 1,
            location: 1,
            distance_km: 1,
            created_at: 1
        }
    },
    {
        $limit: 10
    }
]).toArray();

print("Nearest active drivers within 5 km:");

printjson(results);