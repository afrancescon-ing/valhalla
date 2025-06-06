#ifndef VALHALLA_SIF_COSTFACTORY_H_
#define VALHALLA_SIF_COSTFACTORY_H_

#include <valhalla/proto/options.pb.h>
#include <valhalla/proto_conversions.h>
#include <valhalla/sif/autocost.h>
#include <valhalla/sif/bicyclecost.h>
#include <valhalla/sif/dynamiccost.h>
#include <valhalla/sif/motorcyclecost.h>
#include <valhalla/sif/motorscootercost.h>
#include <valhalla/sif/nocost.h>
#include <valhalla/sif/pedestriancost.h>
#include <valhalla/sif/transitcost.h>
#include <valhalla/sif/truckcost.h>

#include <functional>
#include <map>

namespace valhalla {
namespace sif {

/**
 * Generic factory class for creating objects based on type name.
 */
class CostFactory {
public:
  using factory_function_t = std::function<cost_ptr_t(const Costing& options)>;

  /**
   * Constructor
   */
  CostFactory() {
    Register(Costing::auto_, CreateAutoCost);
    // auto_data_fix was deprecated
    // auto_shorter was deprecated
    Register(Costing::bicycle, CreateBicycleCost);
    Register(Costing::bus, CreateBusCost);
    Register(Costing::taxi, CreateTaxiCost);
    Register(Costing::motor_scooter, CreateMotorScooterCost);
    Register(Costing::motorcycle, CreateMotorcycleCost);
    Register(Costing::pedestrian, CreatePedestrianCost);
    Register(Costing::truck, CreateTruckCost);
    Register(Costing::transit, CreateTransitCost);
    Register(Costing::multimodal, CreateNoCost); // dummy so it behaves like the rest
    Register(Costing::none_, CreateNoCost);
    Register(Costing::bikeshare, CreateBikeShareCost);
  }

  /**
   * Register the callback to create this type of cost
   *
   * @param costing    the cost type that the function creates
   * @param function   the function pointer to call to actually create the cost object
   */
  void Register(const Costing::Type costing, factory_function_t&& function) {
    factory_funcs_.erase(costing);
    factory_funcs_.emplace(costing, std::move(function));
  }

  /**
   * Make a cost from its specified type
   * @param options  pbf with costing type and costing options
   */
  cost_ptr_t Create(const Options& options) const {
    // create the cost using the creation function
    auto found = options.costings().find(options.costing_type());
    if (found != options.costings().end()) {
      return Create(found->second);
    } // if we didnt have costing options we need to use some default ones
    else {
      throw std::runtime_error("No costing options provided to cost factory");
    }
  }

  /**
   * Make a default cost from its specified type
   * @param costing_type  which costing to create
   */
  cost_ptr_t Create(Costing::Type costing_type) const {
    Costing default_costing;
    default_costing.set_type(costing_type);
    return Create(default_costing);
  }

  /**
   * Make a cost from its specified type
   * @param costing  the type of cost to create
   * @param options  pbf with request options
   */
  cost_ptr_t Create(const Costing& costing) const {
    auto itr = factory_funcs_.find(costing.type());
    if (itr == factory_funcs_.end()) {
      auto costing_str = Costing_Enum_Name(costing.type());
      throw std::runtime_error("No costing method found for '" + costing_str + "'");
    }
    // create the cost using the function pointer
    return itr->second(costing);
  }

  mode_costing_t CreateModeCosting(const Options& options, TravelMode& mode) {
    mode_costing_t mode_costing;
    mode = TravelMode::kMaxTravelMode;
    // Set travel mode and construct costing(s) for this type
    for (const auto& costing : kCostingTypeMapping.at(options.costing_type())) {
      valhalla::sif::cost_ptr_t cost = Create(options.costings().find(costing)->second);
      mode = cost->travel_mode();
      mode_costing[static_cast<uint32_t>(mode)] = cost;
    }
    if (options.costing_type() == Costing::multimodal || options.costing_type() == Costing::transit ||
        options.costing_type() == Costing::bikeshare) {
      // For multi-modal we set the initial mode to pedestrian. (TODO - allow other initial modes)
      mode = valhalla::sif::TravelMode::kPedestrian;
    }
    // this should never happen
    if (mode == TravelMode::kMaxTravelMode) {
      throw std::runtime_error("sif::CostFactory couldn't find a valid TravelMode for " +
                               Costing_Enum_Name(options.costing_type()));
    }

    return mode_costing;
  }

private:
  std::map<const Costing::Type, factory_function_t> factory_funcs_;
};

} // namespace sif
} // namespace valhalla

#endif // VALHALLA_SIF_COSTFACTORY_H_
